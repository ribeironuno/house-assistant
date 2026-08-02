defmodule Brain.MealFeedback do
  @moduledoc """
  Meal feedback context.

  Stores likes/dislikes for meals to influence future menu generation.
  """

  import Ecto.Query

  alias Brain.Repo
  alias Brain.Menu.MealFeedback

  def create(attrs) do
    changeset = MealFeedback.changeset(%MealFeedback{}, attrs)

    case Repo.insert(changeset) do
      {:ok, feedback} -> {:ok, feedback}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def summarize(group_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 15)

    feedback =
      from(f in MealFeedback,
        where: f.group_id == ^group_id,
        order_by: [desc: f.inserted_at],
        limit: ^limit
      )
      |> Repo.all()

    likes =
      feedback
      |> Enum.filter(&(&1.sentiment == "like"))
      |> Enum.map(& &1.meal_name)

    dislikes =
      feedback
      |> Enum.filter(&(&1.sentiment == "dislike"))
      |> Enum.map(& &1.meal_name)

    %{likes: likes, dislikes: dislikes}
  end
end
