defmodule Brain.LLM.PromptHelperTest do
  use ExUnit.Case, async: true

  alias Brain.LLM.PromptHelper

  @now ~U[2026-08-02 12:00:00Z]

  setup do
    prompt = PromptHelper.build(@now)
    %{prompt: prompt}
  end

  test "prompt includes current date and weekday", %{prompt: prompt} do
    assert prompt =~ "2026-08-02"
    assert prompt =~ "Sunday"
  end

  test "prompt keeps existing shopping actions", %{prompt: prompt} do
    assert prompt =~ "add_item"
    assert prompt =~ "remove_item"
    assert prompt =~ "list_items"
    assert prompt =~ "clear_items"
    assert prompt =~ "set_reminder"
    assert prompt =~ "ignore"
  end

  test "prompt includes pantry actions", %{prompt: prompt} do
    assert prompt =~ "add_pantry_items"
    assert prompt =~ "remove_pantry_item"
    assert prompt =~ "list_pantry"
    assert prompt =~ "clear_pantry"
  end

  test "prompt includes menu actions", %{prompt: prompt} do
    assert prompt =~ "generate_menu"
    assert prompt =~ "get_recipe"
    assert prompt =~ "rate_meal"
  end

  test "prompt includes output fields", %{prompt: prompt} do
    assert prompt =~ "items"
    assert prompt =~ "constraints"
    assert prompt =~ "sentiment"
  end

  test "prompt has no invented actions like help", %{prompt: prompt} do
    refute prompt =~ "- help"
  end
end
