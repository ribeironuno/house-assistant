defmodule Brain.MealFeedbackTest do
  use BrainWeb.ConnCase, async: true

  alias Brain.Repo
  alias Brain.MealFeedback

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "create persists meal feedback" do
    attrs = %{
      group_id: "group_1",
      meal_name: "Bacalhau à Brás",
      sentiment: "like",
      raw_text: "gostei do bacalhau"
    }

    assert {:ok, feedback} = MealFeedback.create(attrs)
    assert feedback.group_id == "group_1"
    assert feedback.meal_name == "Bacalhau à Brás"
    assert feedback.sentiment == "like"
    assert feedback.raw_text == "gostei do bacalhau"
  end

  test "create validates sentiment is like or dislike" do
    attrs = %{
      group_id: "group_1",
      meal_name: "Bacalhau",
      sentiment: "neutral"
    }

    assert {:error, changeset} = MealFeedback.create(attrs)
    assert "is invalid" in errors_on(changeset).sentiment
  end

  test "create requires group_id, meal_name, and sentiment" do
    assert {:error, changeset} = MealFeedback.create(%{})
    assert "can't be blank" in errors_on(changeset).group_id
    assert "can't be blank" in errors_on(changeset).meal_name
    assert "can't be blank" in errors_on(changeset).sentiment
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%\{(\w+)\}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  test "summarize returns likes and dislikes for group" do
    MealFeedback.create(%{
      group_id: "group_1",
      meal_name: "Bacalhau à Brás",
      sentiment: "like"
    })

    MealFeedback.create(%{
      group_id: "group_1",
      meal_name: "Feijoada",
      sentiment: "dislike"
    })

    MealFeedback.create(%{
      group_id: "group_1",
      meal_name: "Arroz de pato",
      sentiment: "like"
    })

    summary = MealFeedback.summarize("group_1")

    assert "Bacalhau à Brás" in summary.likes
    assert "Arroz de pato" in summary.likes
    assert "Feijoada" in summary.dislikes
  end

  test "summarize respects limit option" do
    for i <- 1..20 do
      MealFeedback.create(%{
        group_id: "group_1",
        meal_name: "Meal #{i}",
        sentiment: "like"
      })
    end

    summary = MealFeedback.summarize("group_1", limit: 10)
    assert length(summary.likes) == 10
  end

  test "summarize returns empty lists for unknown group" do
    summary = MealFeedback.summarize("unknown_group")
    assert summary.likes == []
    assert summary.dislikes == []
  end
end
