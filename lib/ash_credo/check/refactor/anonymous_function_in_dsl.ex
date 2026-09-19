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
      generated public function on the resource module, so the body
      compiles as part of the resource and grows both the module and the
      compile-time dependencies of everything it names.

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

      Ash wraps the value of `change`, `validate`, `prepare` and `calculate`
      in a callback module that cannot implement `atomic/3` or `expression/2`.
      A remote capture there has the same limitation as `fn`, so the check flags
      it too. `run` and `manual` also wrap a remote capture, but the wrapper
      loses no capability, so the check does not flag it. Spark passes a remote
      `&Module.function/arity` through untouched, so in every other option
      it is the fix rather than the defect:

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

      Bodies that run after compilation are ordinary code: Spark does not
      lift and the check does not flag an anonymous function inside
      `def`, `defp`, a macro definition, or `quote`.

      Anonymous functions are fine for prototyping, which is why this
      check is opt-in; silence individual call sites with
      `# credo:disable-for-next-line`.
      """
    ]

  alias AshCredo.Introspection.Block
  alias AshCredo.Orchestration

  # Options whose wrapper module cannot implement `atomic/3` or `expression/2`,
  # so a remote capture has the same limitation as `fn`.
  @wrapped ~w(change validate prepare calculate)a

  # `calculation` is the do-block spelling of `calculate`; both report
  # against the entity a reader recognises.
  @canonical %{calculation: :calculate}

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
        "or name a remote function"
  }

  @generic_advice "Spark lifts it into a generated function on the resource module. " <>
                    "Extract it into a module, or name a remote function " <>
                    "(`&Module.function/arity`)"

  # Heads whose bodies run after compilation, plus the forms that are not
  # DSL at all. Spark lifts nothing inside them.
  @deferred ~w(def defp defmacro defmacrop defguard defguardp defimpl defdelegate defprotocol quote @)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    Orchestration.flat_map_resource_context(source_file, params, fn context, issue_meta ->
      context.module_ast
      |> Block.module_body()
      |> Enum.flat_map(&issues(&1, nil, issue_meta))
    end)
  end

  # A module nested inside the resource owns its own DSL, and has its own
  # resource context when it is one.
  defp issues({:defmodule, _meta, _args}, _option, _issue_meta), do: []

  defp issues({head, _meta, args}, _option, _issue_meta) when head in @deferred and is_list(args),
    do: []

  defp issues({:fn, _meta, _clauses}, option, issue_meta), do: [issue(option, "fn", issue_meta)]

  # Spark passes a remote capture through untouched, so it is only a
  # defect where Ash wraps what it is given.
  defp issues({:&, _meta, [{:/, _, [{{:., _, _}, _, _}, _arity]}]}, option, issue_meta) do
    if name_of(option) in @wrapped, do: [issue(option, "&", issue_meta)], else: []
  end

  defp issues({:&, _meta, _body}, option, issue_meta), do: [issue(option, "&", issue_meta)]

  # A named call is the DSL option any function inside it belongs to.
  defp issues({name, meta, args}, _option, issue_meta) when is_atom(name) and is_list(args),
    do: Enum.flat_map(args, &issues(&1, {name, meta}, issue_meta))

  defp issues({left, right}, option, issue_meta),
    do: Enum.flat_map([left, right], &issues(&1, option, issue_meta))

  defp issues({_call, _meta, args}, option, issue_meta) when is_list(args),
    do: Enum.flat_map(args, &issues(&1, option, issue_meta))

  defp issues(list, option, issue_meta) when is_list(list),
    do: Enum.flat_map(list, &issues(&1, option, issue_meta))

  defp issues(_other, _option, _issue_meta), do: []

  defp issue(option, fallback_trigger, issue_meta) do
    canonical = option |> name_of() |> canonical()
    trigger = if canonical, do: to_string(canonical), else: fallback_trigger

    format_issue(issue_meta,
      message:
        "`#{trigger}` is passed an anonymous function - " <>
          "#{Map.get(@advice, canonical, @generic_advice)}.",
      trigger: trigger,
      line_no: line_of(option)
    )
  end

  defp name_of({name, _meta}), do: name
  defp name_of(nil), do: nil

  defp canonical(nil), do: nil
  defp canonical(name), do: Map.get(@canonical, name, name)

  defp line_of({_name, meta}), do: meta[:line]
  defp line_of(nil), do: 1
end
