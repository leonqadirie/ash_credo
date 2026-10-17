defmodule AshCredo.Check.Refactor.AnonymousFunctionInDsl do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    tags: [:ash],
    explanations: [
      check: """
      Flags anonymous functions (`fn ... end` or `&...` captures) anywhere
      in the resource DSL. Prefer to put the code in its own module and
      refer to that instead.

      Spark lifts every anonymous function in DSL position into a
      generated public function on the resource module. The body then
      lives under a generated name, appears that way in stack traces, and
      cannot be tested or documented on its own. It also makes the resource
      the file where that logic changes. The resource is a compile-time
      dependency of its domain and of every module that reads it at
      compile time, so each edit to an inline function recompiles all of
      them. A callback module is not a compile-time dependency of the
      resource, so an edit there recompiles only that module.

      For changes and validations this is more than style: anonymous
      functions can never participate in atomic execution, because Ash
      cannot inspect what they contain. An update or destroy action
      carrying one either fails its atomicity requirement at runtime or
      forces `require_atomic? false`. Anonymous function changes also
      cannot support batching.

          # Bad - can never be atomic, forces require_atomic? false
          update :update do
            change fn changeset, _context ->
              Ash.Changeset.force_change_attribute(changeset, :slug, slug())
            end
          end

          # Good - module callback, can implement atomic/3
          update :update do
            change MyApp.Changes.SlugifyName
          end

      Calculations have the equivalent limitation through `expression/2`:
      an anonymous function calculation can never supply an expression, so
      the data layer cannot run it and sorting on it raises an
      `UndefinedFunctionError` at runtime. A module using
      `Ash.Resource.Calculation` can implement `expression/2`; an `expr(...)`
      calculation is data-layer-native and is not flagged.

      Ash lifts the callback of `after_action`, `before_action`,
      `after_transaction` and `before_transaction` too, and a hook change
      never runs atomically.

      Ash wraps the value of `change`, `validate`, `prepare` and `calculate`
      in a callback module. For changes, validations and calculations that
      wrapper cannot implement `atomic/3` or `expression/2`, so a remote
      capture there has the same limitation as `fn`. The check flags a
      remote capture in all four, because those callbacks belong in a
      module of their own. It leaves `run` and `manual` alone. Spark passes
      a remote `&Module.function/arity` through untouched, so in every
      other option it is the fix rather than the defect:

          # Bad - lifted into the resource
          action :employed?, :boolean do
            run fn input, context -> ... end
          end

          publish :create, ["messages", :conversation_id] do
            transform fn %{data: message} -> %{id: message.id} end
          end

          # Good
          action :employed?, :boolean do
            run MyApp.Employment.EmployedOn
          end

          publish :create, ["messages", :conversation_id] do
            transform &MyApp.Chat.Notification.message/1
          end

      Spark lifts functions supplied as entity arguments or option values,
      including functions nested in lists, maps and two-element tuples.
      The check walks the same positions. Inside an option value it stops
      at any call, because the compiler evaluates the call before Spark
      sees the value; elsewhere it stops at remote calls, operators and
      Kernel macros. It walks into a local call given as an entity
      argument, because Ash builtins such as `after_action` lift the
      function they receive. A local helper in that position, as in
      `calculate :x, :string, helper(fn -> 1 end)`, is reported even
      though nothing lifts its function.

      Bodies that run after compilation are ordinary code as well: Spark
      does not lift and the check does not flag an anonymous function
      inside `def`, `defp`, a macro definition, or `quote`.

      Anonymous functions are fine for prototyping, which is why this
      check is opt-in; silence individual call sites with
      `# credo:disable-for-next-line`.
      """
    ]

  alias AshCredo.Introspection.Block
  alias AshCredo.Orchestration

  # Options whose callback belongs in a module of its own, so the check flags
  # a remote capture there too. For all but `prepare` the wrapper module also
  # cannot implement `atomic/3` or `expression/2`.
  @wrapped ~w(change validate prepare calculate)a

  # Ash lifts the callback of its hook builtins itself, and a hook change
  # never runs atomically, whatever it is given.
  @hook_advice "a hook change can never be made atomic, so the action needs " <>
                 "`require_atomic? false`. Name a remote function (`&MyApp.Hooks.notify/3`) " <>
                 "to keep the body out of the resource, or move the logic into a module " <>
                 "with `use Ash.Resource.Change` that implements `atomic/3`"

  @advice %{
    change:
      "anonymous function changes can never be made atomic or support batching. " <>
        "Extract it into a module with `use Ash.Resource.Change`",
    validate:
      "anonymous function validations can never be made atomic. " <>
        "Extract it into a module with `use Ash.Resource.Validation`",
    prepare: "Extract it into a module with `use Ash.Resource.Preparation`",
    calculate:
      "anonymous function calculations can never supply an expression, so the data " <>
        "layer cannot run them and sorting on them raises at runtime. Extract it into a " <>
        "module with `use Ash.Resource.Calculation` (which can implement `expression/2`) " <>
        "or use `expr(...)`",
    run:
      "Extract it into a module with `use Ash.Resource.Actions.Implementation`, " <>
        "or name a remote function",
    after_action: @hook_advice,
    before_action: @hook_advice,
    after_transaction: @hook_advice,
    before_transaction: @hook_advice
  }

  @generic_advice "Spark lifts it into a generated function on the resource module. " <>
                    "Extract it into a module, or name a remote function " <>
                    "(`&Module.function/arity`)"

  @impl true
  def run(%SourceFile{} = source_file, params) do
    Orchestration.flat_map_resource_context(source_file, params, fn context, issue_meta ->
      context.module_ast
      |> Block.module_body()
      |> Enum.flat_map(&issues(&1, nil, issue_meta))
    end)
  end

  defp issues({:fn, meta, _clauses}, option, issue_meta),
    do: [issue(option, "fn", meta, issue_meta)]

  # Spark passes a remote capture through untouched, so it is only a
  # defect where Ash wraps what it is given.
  defp issues({:&, meta, [{:/, _, [{{:., _, _}, _, _}, _arity]}]}, option, issue_meta) do
    if canonical(option) in @wrapped, do: [issue(option, "&", meta, issue_meta)], else: []
  end

  defp issues({:&, meta, _body}, option, issue_meta), do: [issue(option, "&", meta, issue_meta)]

  # A do block holds entities. Each entity names its own option.
  defp issues({:__block__, _meta, body}, option, issue_meta), do: issues(body, option, issue_meta)

  # Spark also lifts functions nested in option data. Traverse these
  # containers while keeping the enclosing option name.
  defp issues({:%{}, _meta, pairs}, option, issue_meta) when not is_nil(option),
    do: nested(pairs, option, issue_meta)

  # Stop at Kernel calls, operators and special forms, which the compiler
  # evaluates. Treat other local calls as DSL entities and visit their arguments.
  # Remote calls do not match this clause and fall through without traversal.
  defp issues({name, _meta, args}, _option, issue_meta) when is_atom(name) and is_list(args) do
    if elixir?(name, length(args)),
      do: [],
      else: Enum.flat_map(args, &entity_arg(&1, name, issue_meta))
  end

  # Local calls in a DSL do block may define entities; traverse them.
  defp issues({:do, body}, _option, issue_meta), do: issues(body, nil, issue_meta)

  defp issues({key, value}, _option, issue_meta) when is_atom(key),
    do: option_value(value, key, issue_meta)

  defp issues({left, right}, option, issue_meta) when not is_nil(option),
    do: nested([left, right], option, issue_meta)

  defp issues(list, option, issue_meta) when is_list(list),
    do: Enum.flat_map(list, &issues(&1, option, issue_meta))

  defp issues(_other, _option, _issue_meta), do: []

  # Keyword options always arrive in a list, so a bare 2-tuple argument
  # such as `{:change, &MyApp.Calc.run/2}` is data, not an option.
  defp entity_arg({_left, _right} = tuple, name, issue_meta),
    do: option_value(tuple, name, issue_meta)

  defp entity_arg(arg, name, issue_meta), do: issues(arg, name, issue_meta)

  # Spark checks an option's direct value for a function, then walks the
  # data inside it under the option's name. A call, a block or any other
  # expression in the value is code the compiler runs, so `nested/3` stops
  # there.
  defp option_value({kind, _meta, _args} = value, option, issue_meta) when kind in [:fn, :&],
    do: issues(value, option, issue_meta)

  defp option_value(value, option, issue_meta), do: nested(value, option, issue_meta)

  # Attribute functions in nested data to the enclosing DSL option, even
  # when they appear under a keyword key. Match Spark's traversal: visit
  # containers, preserve remote captures and stop at calls.
  defp nested({:fn, meta, _clauses}, option, issue_meta),
    do: [issue(option, "fn", meta, issue_meta, :nested)]

  defp nested({:&, _, [{:/, _, [{{:., _, _}, _, _}, _arity]}]}, _option, _issue_meta), do: []

  defp nested({:&, meta, _body}, option, issue_meta),
    do: [issue(option, "&", meta, issue_meta, :nested)]

  defp nested({:%{}, _meta, pairs}, option, issue_meta), do: nested(pairs, option, issue_meta)
  defp nested({left, right}, option, issue_meta), do: nested([left, right], option, issue_meta)

  defp nested(list, option, issue_meta) when is_list(list),
    do: Enum.flat_map(list, &nested(&1, option, issue_meta))

  defp nested(_other, _option, _issue_meta), do: []

  defp elixir?(name, arity) do
    Macro.special_form?(name, arity) or Macro.operator?(name, arity) or
      macro_exported?(Kernel, name, arity) or function_exported?(Kernel, name, arity)
  end

  # A function nested in an option's data is not the option's callback,
  # so it gets the generic advice rather than the option's own.
  defp issue(option, fallback_trigger, meta, issue_meta, position \\ :direct) do
    canonical = canonical(option)
    trigger = if canonical, do: to_string(canonical), else: fallback_trigger

    message =
      case position do
        :direct ->
          "`#{trigger}` is passed an anonymous function - " <>
            "#{Map.get(@advice, canonical, @generic_advice)}."

        :nested ->
          "`#{trigger}` holds an anonymous function in its value - #{@generic_advice}."
      end

    format_issue(issue_meta, message: message, trigger: trigger, line_no: meta[:line])
  end

  defp canonical(:calculation), do: :calculate
  defp canonical(name), do: name
end
