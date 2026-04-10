defmodule AshCredo.Introspection.LexicalAliases do
  @moduledoc """
  Shared helpers for the parts of Elixir's lexical alias behavior that
  `AshCredo.Introspection` and `AshCredo.Introspection.AshCallScanner` both need.

  This module does not attempt to model the full lexical environment. It only
  tracks alias frames and resolves literal `defmodule` names into absolute
  module segments using the same rules Elixir applies:

  * visible aliases apply to top-level `defmodule` names
  * nested `defmodule` names are resolved by prepending the enclosing module
  * aliases are scoped lexically and must not leak out of blocks like `if`,
    `case`, `fn`, or `with`
  """

  alias AshCredo.Introspection.Aliases

  @doc """
  Pushes a new lexical alias frame.

  Each frame stores aliases introduced in one lexical scope, such as a module,
  function, branch, or anonymous-function body.
  """
  def push_frame(frames) when is_list(frames), do: [[] | frames]

  @doc """
  Pops the current lexical alias frame.

  Returns an empty frame stack unchanged when no frame is present.
  """
  def pop_frame([_current | frames]), do: frames
  def pop_frame([]), do: []

  @doc """
  Adds alias entries to the current lexical frame.

  Alias entries use the `{alias_segments, target_segments}` shape returned by
  `AshCredo.Introspection.Aliases.alias_entries/1`.
  """
  def put_aliases([current | frames], new_aliases) when is_list(new_aliases) do
    [new_aliases ++ current | frames]
  end

  def put_aliases([], new_aliases) when is_list(new_aliases), do: [new_aliases]

  @doc """
  Flattens the visible alias frames into the alias list seen at the current
  traversal point.
  """
  def current_aliases(frames) when is_list(frames) do
    Enum.concat(frames)
  end

  @doc """
  Resolves a literal `defmodule` name into absolute module segments.

  When `parent_absolute` is empty, the module is top-level and visible aliases
  are applied to its literal segments. When `parent_absolute` is a module path,
  the module is nested and Elixir resolves it by prepending the enclosing path
  without applying lexical aliases to the nested name itself.

  Returns `nil` when the segments are not a literal alias or when the enclosing
  module path is already unknown.
  """
  def absolute_module_segments(literal_segments, parent_absolute, alias_frames)
      when is_list(literal_segments) and is_list(alias_frames) do
    cond do
      not Enum.all?(literal_segments, &is_atom/1) ->
        nil

      is_nil(parent_absolute) ->
        nil

      parent_absolute == [] ->
        Aliases.expand_alias(literal_segments, current_aliases(alias_frames))

      true ->
        parent_absolute ++ literal_segments
    end
  end

  def absolute_module_segments(_literal_segments, _parent_absolute, _alias_frames), do: nil
end
