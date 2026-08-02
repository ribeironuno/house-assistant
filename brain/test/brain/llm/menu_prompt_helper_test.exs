defmodule Brain.LLM.MenuPromptHelperTest do
  use ExUnit.Case, async: true

  alias Brain.LLM.MenuPromptHelper

  @today ~U[2026-08-02 12:00:00Z] |> DateTime.shift_zone!("Europe/Lisbon")

  test "build includes pantry items" do
    pantry = [%Brain.Pantry.Item{name: "bacalhau"}, %Brain.Pantry.Item{name: "batatas"}]

    prompt = MenuPromptHelper.build(pantry, [], %{likes: [], dislikes: []}, "", @today)

    assert prompt =~ "bacalhau"
    assert prompt =~ "batatas"
  end

  test "build includes meal history as recent meals" do
    history = ["Bacalhau com natas", "Feijoada"]

    prompt = MenuPromptHelper.build([], history, %{likes: [], dislikes: []}, "", @today)

    assert prompt =~ "Bacalhau com natas"
    assert prompt =~ "Feijoada"
    assert prompt =~ "do not repeat" or prompt =~ "Não repetir" or prompt =~ "não repetir"
  end

  test "build includes preferences from feedback" do
    preferences = %{likes: ["Bacalhau à Brás"], dislikes: ["Feijoada"]}

    prompt = MenuPromptHelper.build([], [], preferences, "", @today)

    assert prompt =~ "Bacalhau à Brás"
    assert prompt =~ "Feijoada"
  end

  test "build includes constraints verbatim" do
    prompt = MenuPromptHelper.build([], [], %{likes: [], dislikes: []}, "quarta rápido", @today)

    assert prompt =~ "quarta rápido"
  end

  test "build anchors the menu start date to tomorrow" do
    prompt = MenuPromptHelper.build([], [], %{likes: [], dislikes: []}, "", @today)

    assert prompt =~ "2026-08-02"
    assert prompt =~ "tomorrow"
    assert prompt =~ "next 6 days"
  end

  test "build instructs full recipe output per day" do
    prompt = MenuPromptHelper.build([], [], %{likes: [], dislikes: []}, "", @today)

    assert prompt =~ "recipe"
    assert prompt =~ "ingredients"
    assert prompt =~ "steps"
  end

  test "build prompts Portuguese cuisine focus" do
    prompt = MenuPromptHelper.build([], [], %{likes: [], dislikes: []}, "", @today)

    assert prompt =~ "Portuguese"
    assert prompt =~ "bacalhau"
  end
end
