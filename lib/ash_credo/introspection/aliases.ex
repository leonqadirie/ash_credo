defmodule AshCredo.Introspection.Aliases do
  @moduledoc false

  alias AshCredo.Introspection.Block

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

  @doc "Expands module alias segments using the longest-matching alias mapping."
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
