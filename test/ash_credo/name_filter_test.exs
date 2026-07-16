defmodule AshCredo.NameFilterTest do
  use ExUnit.Case, async: true

  alias AshCredo.NameFilter

  test "atom entries match by equality" do
    assert NameFilter.matches_any?(:password, [:password, :token])
    refute NameFilter.matches_any?(:user_password, [:password, :token])
  end

  test "regex entries match against the stringified name" do
    assert NameFilter.matches_any?(:access_token, [~r/_token$/])
    refute NameFilter.matches_any?(:token_count, [~r/_token$/])
  end

  test "a non-atom name never matches a regex" do
    refute NameFilter.matches_any?("password", [~r/password/])
  end

  test "a non-atom name still matches an equal literal entry" do
    assert NameFilter.matches_any?("password", ["password"])
  end

  test "an empty entry list matches nothing" do
    refute NameFilter.matches_any?(:password, [])
  end
end
