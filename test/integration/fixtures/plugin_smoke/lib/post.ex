defmodule AshCredoFixtures.Blog.Post do
  @moduledoc """
  Fixture exercised by `AshCredo.PluginIntegrationTest` for the compiled
  introspection path. The body here is deliberately minimal: the real
  definition lives in `test/support/fixtures/ash_fixtures.ex` and is compiled
  into the test VM. `MissingCodeInterface` can only learn about the
  interface-less actions (e.g. `:draft`) from `Ash.Resource.Info` on that
  compiled module, so any issue it reports proves compiled-introspection
  results survive the whole Credo pipeline (regression guard for issue #187).
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false
end
