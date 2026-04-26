defmodule PluginSmoke.Sample do
  @moduledoc """
  Fixture exercised by `AshCredo.PluginIntegrationTest`. Contains code that
  WOULD trigger several AshCredo checks at varying default toggles, so the
  test can assert which checks the plugin actually wires up.
  """

  # Default-on (`MissingMacroDirective`): `Ash.Query.filter/2` is a macro and
  # `require Ash.Query` is missing. Should fire.
  def filter_published(query) do
    Ash.Query.filter(query, true)
  end

  # Default-off (`UseCodeInterface`): would suggest a code interface, but the
  # check is `false` in the plugin's embedded config. Should NOT fire.
  def get_post do
    Ash.read!(AshCredoFixtures.Blog.Post, action: :read)
  end
end
