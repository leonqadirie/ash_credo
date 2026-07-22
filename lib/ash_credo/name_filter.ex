defmodule AshCredo.NameFilter do
  @moduledoc "Shared name matching for check params that mix atoms and regexes."

  @doc """
  Returns `true` when `name` matches any entry in `entries`.

  Atom (or other literal) entries match by equality. `Regex` entries
  match against the stringified name; a non-atom `name` never matches a
  regex, so non-literal DSL values (e.g. an interpolated field name)
  fall through to "not matched" instead of crashing.
  """
  def matches_any?(name, entries) do
    Enum.any?(entries, &matches?(name, &1))
  end

  defp matches?(name, %Regex{} = regex) when is_atom(name),
    do: Regex.match?(regex, Atom.to_string(name))

  defp matches?(_name, %Regex{}), do: false
  defp matches?(name, entry), do: name == entry
end
