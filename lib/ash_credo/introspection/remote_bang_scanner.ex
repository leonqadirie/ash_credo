defmodule AshCredo.Introspection.RemoteBangScanner do
  @moduledoc """
  Scans a source file's AST for every literal remote bang call -
  `Mod.fun!(args)` where `Mod` is a literal alias - and yields each as
  `{call_ast, expanded_module_segments, fun_name}`.

  Used by `AshCredo.Check.Refactor.RaisingCall`'s compiled-introspection
  pass to find candidate code-interface bang calls.

  Aliases are resolved lexically via `LexicalScopeWalker`'s env. The
  common `alias __MODULE__.Foo` pattern is substituted at declaration
  time by the walker, and use-site `__MODULE__.Foo.bar!()` segments are
  substituted here against the enclosing `defmodule`'s absolute segments,
  so both resolve to the same module as the fully-qualified spelling.
  Calls with a non-literal module (`apply/3`, variable references, bare
  `__MODULE__.fun!()`) are skipped, since the call site cannot be
  resolved to a concrete module at lint time.
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
        fn _node, _scope, state -> state end
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
      # Expand first, substitute second: `expand_alias/2` is a no-op on
      # `__MODULE__`-headed segments, and `resolve_module_self/2` drops
      # calls that cannot resolve to a concrete module (e.g. `__MODULE__`
      # inside a non-literal `defmodule unquote(...)`) - `Module.concat/1`
      # would raise on them.
      resolved =
        segments
        |> Aliases.expand_alias(LexicalScopeWalker.env(scope))
        |> Aliases.resolve_module_self(LexicalScopeWalker.current_module_segments(scope))

      case resolved do
        {:ok, expanded} -> %{state | calls: [{call_ast, expanded, fun_name} | state.calls]}
        :error -> state
      end
    else
      state
    end
  end

  defp on_enter(_node, _scope, state), do: state

  defp bang?(fun_name) do
    fun_name |> Atom.to_string() |> String.ends_with?("!")
  end
end
