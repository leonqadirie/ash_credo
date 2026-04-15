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

  alias AshCredo.Introspection.{Aliases, LexicalAliases}

  @compiled_segments [:AshCredo, :Introspection, :Compiled]
  @scope_keys ~w(do else after rescue catch)a
  @lexical_scope_nodes ~w(defmodule def defp defmacro defmacrop fn if unless case cond with try receive for)a

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
    {_, state} =
      Macro.traverse(ast, initial_scan_state(), &enter_node/2, &leave_node/2)

    Map.take(state, [:compiled_alias_line, :has_wrapper_call?])
  end

  defp initial_scan_state do
    %{
      alias_frames: [[]],
      compiled_alias_line: nil,
      has_wrapper_call?: false
    }
  end

  defp enter_node({scope_key, _body} = node, state) when scope_key in @scope_keys do
    {node, push_alias_frame(state)}
  end

  defp enter_node({:->, _, [_args, _body]} = node, state) do
    {node, push_alias_frame(state)}
  end

  defp enter_node({node_name, _, _} = node, state) when node_name in @lexical_scope_nodes do
    {node, push_alias_frame(state)}
  end

  defp enter_node({:alias, meta, _} = node, state) do
    alias_entries = Aliases.alias_entries(node)

    state =
      state
      |> maybe_record_compiled_alias_line(meta[:line], alias_entries)
      |> put_aliases(alias_entries)

    {node, state}
  end

  defp enter_node({{:., _, [module_ast, :with_compiled_check]}, _, args} = node, state)
       when is_list(args) do
    state =
      if length(args) == 2 and compiled_module_ref?(module_ast, state) do
        %{state | has_wrapper_call?: true}
      else
        state
      end

    {node, state}
  end

  defp enter_node(node, state), do: {node, state}

  defp leave_node({scope_key, _body} = node, state) when scope_key in @scope_keys do
    {node, pop_alias_frame(state)}
  end

  defp leave_node({:->, _, [_args, _body]} = node, state) do
    {node, pop_alias_frame(state)}
  end

  defp leave_node({node_name, _, _} = node, state) when node_name in @lexical_scope_nodes do
    {node, pop_alias_frame(state)}
  end

  defp leave_node(node, state), do: {node, state}

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

  defp compiled_module_ref?({:__aliases__, _, segments}, state) when is_list(segments) do
    Aliases.expand_alias(segments, current_aliases(state)) == @compiled_segments
  end

  defp compiled_module_ref?(_module_ast, _state), do: false

  defp push_alias_frame(state) do
    update_in(state.alias_frames, &LexicalAliases.push_frame/1)
  end

  defp pop_alias_frame(%{alias_frames: frames} = state) do
    %{state | alias_frames: LexicalAliases.pop_frame(frames)}
  end

  defp put_aliases(state, alias_entries) do
    update_in(state.alias_frames, &LexicalAliases.put_aliases(&1, alias_entries))
  end

  defp current_aliases(%{alias_frames: frames}) do
    LexicalAliases.current_aliases(frames)
  end

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
