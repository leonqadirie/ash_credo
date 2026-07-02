defmodule AshCredo.Introspection.Aliases do
  @moduledoc false

  alias AshCredo.Introspection.Block

  @directive_kinds ~w(alias require import)a

  @doc """
  Returns a fresh `Macro.Env` for accumulating lexical directives.

  Built via `Code.env_for_eval/1`, so `Kernel` is pre-required and
  pre-imported exactly as in any real compilation unit. Only observable
  when a consumer asks `Macro.Env.required?(env, Kernel)` before any
  directive was applied - which mirrors real Elixir semantics anyway.
  """
  def base_env do
    Code.env_for_eval(file: "nofile")
  end

  @doc """
  Applies an `alias`/`require`/`import` directive AST node to `env` and
  returns the updated env. Malformed or unresolvable directives leave the
  env unchanged (graceful skip), matching how unparsable directives
  produced no alias entry before.

  `enclosing` is the absolute segment list of the innermost literal
  `defmodule`, or `nil` when unknown; it substitutes a leading
  `__MODULE__` in the directive target (`alias __MODULE__.Post`) at
  declaration time, which is where Elixir itself resolves it.

  `require Mod, as: Q` registers both the require and the alias.
  `import Mod` is registered via `Macro.Env.define_require/4` rather than
  `define_import/4`: consumers only ask "is a require satisfied here?"
  (import implies require in Elixir), and `define_import` raises for
  modules not loaded in the linting VM, which source-only references
  regularly are.
  """
  def apply_directive(%Macro.Env{} = env, directive_ast, enclosing) do
    directive_ast
    |> directive_targets()
    |> Enum.reduce(env, fn {kind, meta, target_segments, as_opts}, acc ->
      apply_target(acc, kind, meta, target_segments, as_opts, enclosing)
    end)
  end

  @doc """
  Resolves alias segments to a module atom through `env`, falling back to
  plain concatenation when no alias matches. Returns `:error` when the
  segments are not a non-empty list of plain atoms (e.g. they still carry
  an `unquote` or `__MODULE__` node).
  """
  def expand_to_module(segments, %Macro.Env{} = env) when is_list(segments) do
    if atom_segments?(segments) do
      case Macro.Env.expand_alias(env, [], segments) do
        {:alias, module} -> {:ok, module}
        :error -> {:ok, Module.concat(segments)}
      end
    else
      :error
    end
  end

  def expand_to_module(_segments, %Macro.Env{}), do: :error

  @doc """
  Extracts the literal alias segments from a `defmodule` AST node, or `nil`
  when the module name is not a literal alias (e.g. `Module.concat(...)`).
  """
  def defmodule_literal_segments({:defmodule, _, [{:__aliases__, _, segs}, _]})
      when is_list(segs), do: segs

  def defmodule_literal_segments(_), do: nil

  @doc """
  Resolves a literal `defmodule` name into absolute module segments through
  the visible env.

  When `parent_absolute` is empty, the module is top-level and visible
  aliases apply to its literal segments. When it is a module path, the
  module is nested and Elixir resolves it by prepending the enclosing path
  without applying lexical aliases to the nested name itself. Returns `nil`
  when the segments are not a literal alias or the enclosing module path is
  already unknown.
  """
  def absolute_module_segments(literal_segments, parent_absolute, %Macro.Env{} = env)
      when is_list(literal_segments) do
    cond do
      not Enum.all?(literal_segments, &is_atom/1) -> nil
      is_nil(parent_absolute) -> nil
      parent_absolute == [] -> expand_alias(literal_segments, env)
      true -> parent_absolute ++ literal_segments
    end
  end

  def absolute_module_segments(_literal_segments, _parent_absolute, %Macro.Env{}), do: nil

  @doc """
  Returns top-level alias mappings in a module body, optionally filtered by
  `:before_line`. Covers `alias` directives and `require ..., as:` (which
  sets up the same alias).
  """
  def module_aliases(module_ast, opts \\ [])

  def module_aliases({:defmodule, _, _} = module_ast, opts) do
    before_line = Keyword.get(opts, :before_line)

    module_ast
    |> Block.module_body()
    |> Enum.flat_map(fn
      {directive, meta, _} = directive_ast when directive in [:alias, :require] ->
        if alias_before?(meta[:line], before_line) do
          alias_entries(directive_ast)
        else
          []
        end

      _stmt ->
        []
    end)
  end

  def module_aliases(_, _opts), do: []

  @doc """
  Expands module alias segments. With a `Macro.Env`, resolution is the
  compiler's own (`Macro.Env.expand_alias/4`); with a legacy alias entry
  list, the longest-matching mapping applies. Both are segments-in /
  segments-out: unresolvable input (non-atom segments, no match) is
  returned unchanged.
  """
  def expand_alias(segments, %Macro.Env{} = env) when is_list(segments) do
    with true <- atom_segments?(segments),
         {:alias, module} <- Macro.Env.expand_alias(env, [], segments),
         resolved when is_list(resolved) <- elixir_module_segments(module) do
      resolved
    else
      _ -> segments
    end
  end

  def expand_alias(segments, aliases) when is_list(segments) and is_list(aliases) do
    matches =
      Enum.filter(aliases, fn
        {alias_segments, _target_segments} -> List.starts_with?(segments, alias_segments)
        _ -> false
      end)

    case Enum.max_by(
           matches,
           fn {alias_segments, _target_segments} -> length(alias_segments) end,
           fn -> nil end
         ) do
      {alias_segments, target_segments} ->
        target_segments ++ Enum.drop(segments, length(alias_segments))

      nil ->
        segments
    end
  end

  def expand_alias(segments, _aliases), do: segments

  @doc """
  Substitutes `__MODULE__` elements in expanded alias segments with the
  enclosing `defmodule`'s absolute segments (`alias __MODULE__.Post` targets
  carry the raw `__MODULE__` AST tuple). Returns `{:ok, segments}` only when
  every resulting segment is an atom - `Module.concat/1` raises on anything
  else - and `:error` when substitution is impossible (no enclosing literal
  module) or non-atom segments remain.
  """
  def resolve_module_self(segments, enclosing) when is_list(segments) do
    resolved =
      Enum.flat_map(segments, fn
        {:__MODULE__, _, _} when is_list(enclosing) and enclosing != [] -> enclosing
        other -> [other]
      end)

    if Enum.all?(resolved, &is_atom/1), do: {:ok, resolved}, else: :error
  end

  @doc "Resolves a module reference or segments within a module or resource context."
  def resolved_module_ref(ref_or_segments, module_or_context, opts \\ [])

  def resolved_module_ref({:__aliases__, meta, segments}, module_or_context, opts) do
    resolved_module_ref(
      segments,
      module_or_context,
      Keyword.put_new(opts, :before_line, meta[:line])
    )
  end

  def resolved_module_ref(segments, %{env: %Macro.Env{} = env}, _opts) when is_list(segments) do
    expand_alias(segments, env)
  end

  def resolved_module_ref(segments, module_or_context, opts) when is_list(segments) do
    expand_alias(segments, context_aliases(module_or_context, opts))
  end

  def resolved_module_ref(other, _module_or_context, _opts), do: other

  @doc "Returns true if a module reference resolves to the given target segments."
  def module_ref?(ref_or_segments, module_or_context, target_segments, opts \\ []) do
    resolved_module_ref(ref_or_segments, module_or_context, opts) == target_segments
  end

  @doc "Extracts `{alias_segments, target_segments}` pairs from an alias AST node."
  def alias_entries({:alias, _, [{:__aliases__, _, target_segments}]}) do
    [{default_alias(target_segments), target_segments}]
  end

  def alias_entries({:alias, _, [{:__aliases__, _, target_segments}, opts]}) when is_list(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, alias_segments} -> [{alias_segments, target_segments}]
      _ -> [{default_alias(target_segments), target_segments}]
    end
  end

  def alias_entries(
        {:alias, _, [{{:., _, [{:__aliases__, _, prefix_segments}, :{}]}, _, suffix_aliases}]}
      )
      when is_list(suffix_aliases) do
    grouped_alias_entries(prefix_segments, suffix_aliases)
  end

  def alias_entries(
        {:alias, _,
         [{{:., _, [{:__aliases__, _, prefix_segments}, :{}]}, _, suffix_aliases}, opts]}
      )
      when is_list(suffix_aliases) and is_list(opts) do
    grouped_alias_entries(prefix_segments, suffix_aliases)
  end

  # `alias __MODULE__.{Post, Comment}` - the prefix is the raw __MODULE__
  # AST tuple, carried into the target segments for consumers to resolve
  # via `resolve_module_self/2`.
  def alias_entries(
        {:alias, _, [{{:., _, [{:__MODULE__, _, _} = self_ref, :{}]}, _, suffix_aliases}]}
      )
      when is_list(suffix_aliases) do
    grouped_alias_entries([self_ref], suffix_aliases)
  end

  def alias_entries(
        {:alias, _, [{{:., _, [{:__MODULE__, _, _} = self_ref, :{}]}, _, suffix_aliases}, opts]}
      )
      when is_list(suffix_aliases) and is_list(opts) do
    grouped_alias_entries([self_ref], suffix_aliases)
  end

  # `require Mod, as: Alias` sets up the alias exactly like
  # `alias Mod, as: Alias` (a documented `require` option, and the
  # idiomatic one-liner for macro modules like `Ash.Query`). A `require`
  # without `as:` creates no alias.
  def alias_entries({:require, _, [{:__aliases__, _, target_segments}, opts]})
      when is_list(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, alias_segments} -> [{alias_segments, target_segments}]
      _ -> []
    end
  end

  def alias_entries(_), do: []

  defp alias_before?(_alias_line, nil), do: true

  defp alias_before?(alias_line, before_line)
       when is_integer(alias_line) and is_integer(before_line), do: alias_line < before_line

  defp alias_before?(_alias_line, _before_line), do: false

  defp grouped_alias_entries(prefix_segments, suffix_aliases) do
    Enum.flat_map(suffix_aliases, fn
      {:__aliases__, _, suffix_segments} ->
        target_segments = prefix_segments ++ suffix_segments
        [{default_alias(target_segments), target_segments}]

      _ ->
        []
    end)
  end

  defp default_alias([last]), do: [last]
  defp default_alias([_head | rest]), do: default_alias(rest)
  defp default_alias([]), do: [nil]

  # ── Macro.Env directive machinery ──

  # Normalizes a directive AST node into `{kind, meta, target_segments,
  # as_opts}` tuples. Grouped forms (`alias P.{A, B}`) yield one tuple per
  # suffix; `require`/`import` share the same shapes. Anything else yields
  # no tuples. `as_opts` is `[]`, `[as: Module]`, or the `:invalid` marker
  # for a multi-segment `as:` (invalid Elixir - the whole entry is skipped
  # rather than misregistered under a guessed name).
  defp directive_targets({kind, meta, [target]}) when kind in @directive_kinds do
    directive_targets({kind, meta, [target, []]})
  end

  defp directive_targets({kind, meta, [{:__aliases__, _, segments}, opts]})
       when kind in @directive_kinds and is_list(opts) do
    [{kind, meta, segments, as_option(opts)}]
  end

  defp directive_targets({kind, meta, [{{:., _, [prefix, :{}]}, _, suffixes}, opts]})
       when kind in @directive_kinds and is_list(suffixes) and is_list(opts) do
    case grouped_prefix_segments(prefix) do
      nil ->
        []

      prefix_segments ->
        for {:__aliases__, _, suffix_segments} <- suffixes do
          {kind, meta, prefix_segments ++ suffix_segments, []}
        end
    end
  end

  defp directive_targets(_), do: []

  defp grouped_prefix_segments({:__aliases__, _, prefix_segments}), do: prefix_segments
  defp grouped_prefix_segments({:__MODULE__, _, _} = self_ref), do: [self_ref]
  defp grouped_prefix_segments(_), do: nil

  defp as_option(opts) do
    case Keyword.get(opts, :as) do
      nil ->
        []

      {:__aliases__, _, [name]} when is_atom(name) and not is_nil(name) ->
        [as: Module.concat([name])]

      {:__aliases__, _, _} ->
        :invalid

      _other ->
        []
    end
  end

  defp apply_target(env, _kind, _meta, _segments, :invalid, _enclosing), do: env

  defp apply_target(env, kind, meta, segments, as_opts, enclosing) do
    with {:ok, substituted} <- substitute_self(segments, enclosing),
         {:ok, module} <- expand_to_module(substituted, env) do
      define(env, kind, meta, module, as_opts)
    else
      _ -> env
    end
  end

  defp substitute_self([{:__MODULE__, _, _} | rest], enclosing)
       when is_list(enclosing) and enclosing != [] do
    {:ok, enclosing ++ rest}
  end

  defp substitute_self([{:__MODULE__, _, _} | _rest], _enclosing), do: :error
  defp substitute_self(segments, _enclosing), do: {:ok, segments}

  defp define(env, :alias, meta, module, as_opts) do
    keep_on_error(env, Macro.Env.define_alias(env, meta, module, as_opts ++ [trace: false]))
  end

  defp define(env, kind, meta, module, as_opts) when kind in [:require, :import] do
    keep_on_error(env, Macro.Env.define_require(env, meta, module, as_opts ++ [trace: false]))
  end

  defp keep_on_error(_env, {:ok, updated}), do: updated
  defp keep_on_error(env, {:error, _}), do: env

  defp atom_segments?(segments) do
    segments != [] and Enum.all?(segments, &(is_atom(&1) and not is_nil(&1)))
  end

  # `Module.split/1` raises for non-Elixir atoms; alias targets extracted
  # from `__aliases__` nodes are always Elixir modules, but stay defensive.
  defp elixir_module_segments(module) do
    case Atom.to_string(module) do
      "Elixir." <> _rest -> module |> Module.split() |> Enum.map(&String.to_atom/1)
      _other -> nil
    end
  end

  defp context_aliases(%{module_ast: module_ast, aliases: aliases}, opts) do
    case Keyword.get(opts, :before_line) do
      nil -> aliases
      _ -> module_aliases(module_ast, opts)
    end
  end

  defp context_aliases(%{aliases: aliases}, _opts) when is_list(aliases), do: aliases

  defp context_aliases({:defmodule, _, _} = module_ast, opts),
    do: module_aliases(module_ast, opts)

  defp context_aliases(_, _opts), do: []
end
