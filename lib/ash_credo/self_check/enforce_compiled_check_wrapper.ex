defmodule AshCredo.SelfCheck.EnforceCompiledCheckWrapper do
  @moduledoc false

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Every check under `lib/ash_credo/check/` that aliases
      `AshCredo.Introspection.Compiled` must call `with_compiled_check/2`
      somewhere in its body - directly, or through one of the
      `AshCredo.Orchestration` harnesses that wrap it
      (`compiled_check_on_named_resources/4`,
      `compiled_check_on_loadable_resources/4`).

      `with_compiled_check/2` detects whether Ash is loaded in the
      current VM and, when it is not, emits a single informational
      diagnostic instead of crashing. Omitting the wrapper means the
      check will raise at runtime when a user runs `mix credo` without
      `mix compile` or without Ash installed.

      If you are adding a new compiled check, prefer an Orchestration
      harness:

          Orchestration.compiled_check_on_named_resources(
            source_file,
            params,
            __MODULE__,
            &check_resource/3
          )

      or wrap your introspection logic directly:

          CompiledIntrospection.with_compiled_check(
            fn -> Orchestration.ash_missing_issue(issue_meta, __MODULE__) end,
            fn -> ... end
          )
      """
    ]

  alias AshCredo.Introspection.{Aliases, LexicalScopeWalker}

  @compiled_segments [:AshCredo, :Introspection, :Compiled]
  @orchestration_segments [:AshCredo, :Orchestration]

  # Orchestration harnesses that call `with_compiled_check/2` internally;
  # calling one satisfies this check. Keep in sync with
  # `AshCredo.Orchestration`.
  @orchestration_wrappers ~w(compiled_check_on_named_resources compiled_check_on_loadable_resources)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if check_file?(source_file.filename) do
      ast = Credo.SourceFile.ast(source_file)

      case compiled_usage(ast) do
        %{compiled_alias_line: nil} ->
          []

        %{has_wrapper_call?: true} ->
          []

        %{compiled_alias_line: line} ->
          issue_meta = IssueMeta.for(source_file, params)

          [
            format_issue(issue_meta,
              message:
                "Aliases `AshCredo.Introspection.Compiled` but never calls " <>
                  "`with_compiled_check/2` -- compiled checks must use this " <>
                  "wrapper to handle missing Ash gracefully.",
              line_no: line,
              trigger: "AshCredo.Introspection.Compiled"
            )
          ]
      end
    else
      []
    end
  end

  defp compiled_usage(ast) do
    {state, _scope} =
      LexicalScopeWalker.traverse(
        ast,
        %{compiled_alias_line: nil, has_wrapper_call?: false},
        &on_enter/3,
        fn _node, _scope, acc -> acc end
      )

    state
  end

  defp on_enter({:alias, meta, _} = node, _scope, state) do
    maybe_record_compiled_alias_line(state, meta[:line], Aliases.alias_entries(node))
  end

  defp on_enter({{:., _, [module_ast, :with_compiled_check]}, _, args}, scope, state)
       when is_list(args) do
    if match?([_, _], args) and compiled_module_ref?(module_ast, scope) do
      %{state | has_wrapper_call?: true}
    else
      state
    end
  end

  defp on_enter({{:., _, [module_ast, wrapper]}, _, args}, scope, state)
       when wrapper in @orchestration_wrappers and is_list(args) do
    if match?([_, _, _, _], args) and orchestration_module_ref?(module_ast, scope) do
      %{state | has_wrapper_call?: true}
    else
      state
    end
  end

  defp on_enter(_node, _scope, state), do: state

  defp maybe_record_compiled_alias_line(%{compiled_alias_line: nil} = state, line, alias_entries) do
    if Enum.any?(alias_entries, &compiled_alias_entry?/1) do
      %{state | compiled_alias_line: line}
    else
      state
    end
  end

  defp maybe_record_compiled_alias_line(state, _line, _alias_entries), do: state

  defp compiled_alias_entry?({_alias_segments, @compiled_segments}), do: true
  defp compiled_alias_entry?(_alias_entry), do: false

  defp compiled_module_ref?({:__aliases__, _, segments}, scope) when is_list(segments) do
    Aliases.expand_alias(segments, LexicalScopeWalker.aliases(scope)) == @compiled_segments
  end

  defp compiled_module_ref?(_module_ast, _scope), do: false

  defp orchestration_module_ref?({:__aliases__, _, segments}, scope) when is_list(segments) do
    Aliases.expand_alias(segments, LexicalScopeWalker.aliases(scope)) == @orchestration_segments
  end

  defp orchestration_module_ref?(_module_ast, _scope), do: false

  defp check_file?(filename) when is_binary(filename) do
    filename
    |> Path.split()
    |> tail_from_last_lib()
    |> then(&match?(["lib", "ash_credo", "check" | _], &1))
  end

  defp tail_from_last_lib(segments) when is_list(segments) do
    segments
    |> Stream.with_index()
    |> Enum.reduce(nil, fn
      {"lib", idx}, _acc -> idx
      {_segment, _idx}, acc -> acc
    end)
    |> case do
      nil -> []
      idx -> Enum.drop(segments, idx)
    end
  end
end
