defmodule AshCredo.Introspection.Aliases do
  @moduledoc false

  alias AshCredo.Introspection

  @doc "Returns top-level alias mappings in a module body, optionally filtered by `:before_line`."
  def module_aliases(module_ast, opts \\ [])

  def module_aliases({:defmodule, _, _} = module_ast, opts) do
    before_line = Keyword.get(opts, :before_line)

    Enum.reduce(Introspection.module_body(module_ast), [], fn
      {:alias, meta, _} = alias_ast, aliases ->
        if alias_before?(meta[:line], before_line) do
          alias_entries(alias_ast) ++ aliases
        else
          aliases
        end

      _stmt, aliases ->
        aliases
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

  def expand_alias(other, _aliases), do: other

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

  defp default_alias(target_segments), do: [List.last(target_segments)]

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
