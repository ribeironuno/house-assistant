defmodule Brain.LLM.MenuPromptHelperTest do
  use ExUnit.Case, async: true

  alias Brain.LLM.MenuPromptHelper

  @today ~U[2026-08-02 12:00:00Z] |> DateTime.shift_zone!("Europe/Lisbon")

  defp build(args \\ []) do
    pantry = Keyword.get(args, :pantry, [])
    history = Keyword.get(args, :history, [])
    preferences = Keyword.get(args, :preferences, %{likes: [], dislikes: []})
    constraints = Keyword.get(args, :constraints, "")

    MenuPromptHelper.build(pantry, history, preferences, constraints, @today)
  end

  test "build includes pantry items in the user message" do
    pantry = [%Brain.Pantry.Item{name: "bacalhau"}, %Brain.Pantry.Item{name: "batatas"}]

    {_system_prompt, user_prompt} = build(pantry: pantry)

    assert user_prompt =~ "bacalhau"
    assert user_prompt =~ "batatas"
  end

  test "build includes meal history as recent meals" do
    history = ["Bacalhau com natas", "Feijoada"]

    {_system_prompt, user_prompt} = build(history: history)

    assert user_prompt =~ "Bacalhau com natas"
    assert user_prompt =~ "Feijoada"
  end

  test "build includes preferences from feedback" do
    preferences = %{likes: ["Bacalhau à Brás"], dislikes: ["Feijoada"]}

    {_system_prompt, user_prompt} = build(preferences: preferences)

    assert user_prompt =~ "Bacalhau à Brás"
    assert user_prompt =~ "Feijoada"
  end

  test "build includes constraints verbatim" do
    {_system_prompt, user_prompt} = build(constraints: "quarta rápido")

    assert user_prompt =~ "quarta rápido"
  end

  test "build keeps pantry, history, and preferences out of the system prompt" do
    pantry = [%Brain.Pantry.Item{name: "atum"}]
    history = ["Arroz de tamboril"]
    constraints = "só de carne"
    preferences = %{likes: ["Tapioca"], dislikes: []}

    {system_prompt, _user_prompt} =
      build(pantry: pantry, history: history, constraints: constraints, preferences: preferences)

    refute system_prompt =~ "atum"
    refute system_prompt =~ "Arroz de tamboril"
    refute system_prompt =~ "Tapioca"

    # Constraints ARE expected in the system prompt (user-supplied hard rules).
    assert system_prompt =~ "só de carne"
  end

  test "build caps constraints to 500 characters" do
    long_constraints = String.duplicate("a", 600)

    {system_prompt, _user_prompt} = build(constraints: long_constraints)

    assert system_prompt =~ String.duplicate("a", 500)
    refute system_prompt =~ String.duplicate("a", 501)
  end

  test "build anchors the menu start date to tomorrow in the system prompt" do
    {system_prompt, _user_prompt} = build()

    assert system_prompt =~ "2026-08-02"
    assert system_prompt =~ "tomorrow"
    assert system_prompt =~ "next 6 days"
  end

  test "build instructs full recipe output per day" do
    {system_prompt, _user_prompt} = build()

    assert system_prompt =~ "recipe"
    assert system_prompt =~ "ingredients"
    assert system_prompt =~ "steps"
  end

  test "build prompts Portuguese cuisine focus" do
    {system_prompt, _user_prompt} = build()

    assert system_prompt =~ "Portuguese"
    assert system_prompt =~ "bacalhau"
  end
end
