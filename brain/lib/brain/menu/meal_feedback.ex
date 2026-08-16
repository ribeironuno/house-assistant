defmodule Brain.Menu.MealFeedback do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema for meal feedback (likes/dislikes).
  """

  schema "meal_feedback" do
    field(:group_id, :string)
    field(:meal_name, :string)
    field(:sentiment, :string)
    field(:raw_text, :string)

    timestamps()
  end

  def changeset(meal_feedback, attrs) do
    meal_feedback
    |> cast(attrs, [:group_id, :meal_name, :sentiment, :raw_text])
    |> validate_required([:group_id, :meal_name, :sentiment])
    |> validate_inclusion(:sentiment, ["like", "dislike"])
    |> foreign_key_constraint(:group_id)
  end
end
