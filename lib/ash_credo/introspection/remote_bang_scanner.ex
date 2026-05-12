defmodule AshCredo.Introspection.RemoteBangScanner do
  @moduledoc """
  Scans a source file's AST for every literal remote bang call -
  `Mod.fun!(args)` where `Mod` is a literal alias - and yields each as
  `{call_ast, expanded_module_segments, fun_name}`.

  Used by `AshCredo.Check.Refactor.RaisingCall`'s compiled-introspection
  pass to find candidate code-interface bang calls.

  Aliases are resolved lexically via `LexicalScopeWalker`, including the
  common `alias __MODULE__.Foo` pattern: when an expanded alias contains
  `__MODULE__`, the scanner substitutes the enclosing `defmodule`'s
  absolute segments so `Foo.archive!()` resolves to the same module as
  the fully-qualified spelling. Calls with a non-literal module
  (`apply/3`, variable references, bare `__MODULE__.fun!()`) are skipped,
  since the call site cannot be resolved to a concrete module at lint time.
  """

  alias AshCredo.Introspection.{Aliases, LexicalScopeWalker}

  @doc """
  Returns all `Mod.fun!(args)` call sites in `source_file` as
  `{call_ast, expanded_module_segments, fun_name}` tuples. Non-bang
  remote calls and dynamic call shapes are omitted.
  """
  def calls(source_file) do
    {%{calls: calls}, _scope} =
      source_file
      |> Credo.SourceFile.ast()
      |> LexicalScopeWalker.traverse(
        %{calls: []},
        &on_enter/3,
        fn _node, _scope, state -> state end,
        track_module_stack: true
      )

    Enum.reverse(calls)
  end

  defp on_enter(
         {{:., _, [{:__aliases__, _, segments}, fun_name]}, _meta, args} = call_ast,
         scope,
         state
       )
       when is_list(args) and is_atom(fun_name) and is_list(segments) do
    if bang?(fun_name) do
      expanded =
        segments
        |> Aliases.expand_alias(LexicalScopeWalker.aliases(scope))
        |> resolve_module_self(LexicalScopeWalker.current_module_segments(scope))

      # After substituting `__MODULE__` with the enclosing module's segments,
      # any remaining non-atoms (e.g. `__MODULE__` inside a non-literal
      # `defmodule unquote(...)`) mean we still cannot resolve to a concrete
      # module. `Module.concat/1` would raise, so drop the call.
      if Enum.all?(expanded, &is_atom/1) do
        %{state | calls: [{call_ast, expanded, fun_name} | state.calls]}
      else
        state
      end
    else
      state
    end
  end

  defp on_enter(_node, _scope, state), do: state

  defp resolve_module_self(segments, nil), do: segments

  defp resolve_module_self(segments, enclosing) when is_list(enclosing) do
    Enum.flat_map(segments, fn
      {:__MODULE__, _, _} -> enclosing
      other -> [other]
    end)
  end

  defp bang?(fun_name) do
    fun_name |> Atom.to_string() |> String.ends_with?("!")
  end
end
