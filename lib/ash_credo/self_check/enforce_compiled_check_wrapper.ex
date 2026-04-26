defmodule AshCredo.SelfCheck.EnforceCompiledCheckWrapper do
  @moduledoc false

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Every check under `lib/ash_credo/check/` that aliases
      `AshCredo.Introspection.Compiled` must call `with_compiled_check/2`
      somewhere in its body.

      `with_compiled_check/2` detects whether Ash is loaded in the
      current VM and, when it is not, emits a single informational
      diagnostic instead of crashing. Omitting the wrapper means the
      check will raise at runtime when a user runs `mix credo` without
      `mix compile` or without Ash installed.

      If you are adding a new compiled check, wrap your introspection
      logic like the existing compiled checks do:

          CompiledIntrospection.with_compiled_check(
            fn -> missing_ash_issue(issue_meta) end,
            fn -> ... end
          )
      """
    ]

  alias AshCredo.Introspection.{Aliases, LexicalScopeWalker}

  @compiled_segments [:AshCredo, :Introspection, :Compiled]

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
    if length(args) == 2 and compiled_module_ref?(module_ast, scope) do
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

  defp check_file?(filename) when is_binary(filename) do
    filename
    |> Path.split()
    |> tail_from_last_lib()
    |> case do
      ["lib", "ash_credo", "check" | _] -> true
      _ -> false
    end
  end

  defp tail_from_last_lib(segments) when is_list(segments) do
    case Enum.reduce(Enum.with_index(segments), nil, fn
           {"lib", idx}, _acc -> idx
           {_segment, _idx}, acc -> acc
         end) do
      nil -> []
      idx -> Enum.drop(segments, idx)
    end
  end
end
