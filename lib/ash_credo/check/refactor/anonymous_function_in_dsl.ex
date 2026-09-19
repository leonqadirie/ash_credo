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

      Spark lifts a function in three positions only: the direct value of
      an entity argument, the direct value of an option, and a value in a
      keyword list under its key. It returns every other value unchanged,
      so the check reports those three positions and stops everywhere
      else. A function the compiler evaluates before Spark sees it, such
      as `default: Enum.map([:read], fn t -> t end)`, is ordinary code.

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

  # Spark lifts a function only as the direct value of an entity argument,
  # an option or a keyword-list value. The compiler evaluates a Kernel
  # macro, an operator, a special form and a remote call as ordinary code,
  # so the walk stops there.
  defp issues({name, _meta, args}, _option, issue_meta) when is_atom(name) and is_list(args) do
    if elixir?(name, length(args)),
      do: [],
      else: Enum.flat_map(args, &issues(&1, name, issue_meta))
  end

  defp issues({key, value}, _option, issue_meta) when is_atom(key),
    do: issues(value, key, issue_meta)

  defp issues(list, option, issue_meta) when is_list(list),
    do: Enum.flat_map(list, &issues(&1, option, issue_meta))

  defp issues(_other, _option, _issue_meta), do: []

  defp elixir?(name, arity) do
    Macro.special_form?(name, arity) or Macro.operator?(name, arity) or
      macro_exported?(Kernel, name, arity) or function_exported?(Kernel, name, arity)
  end

  defp issue(option, fallback_trigger, meta, issue_meta) do
    canonical = canonical(option)
    trigger = if canonical, do: to_string(canonical), else: fallback_trigger

    format_issue(issue_meta,
      message:
        "`#{trigger}` is passed an anonymous function - " <>
          "#{Map.get(@advice, canonical, @generic_advice)}.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end

  defp canonical(:calculation), do: :calculate
  defp canonical(name), do: name
end
