defmodule Brain.Repo.Migrations.CreateMealFeedback do
  use Ecto.Migration

  def change do
    create table(:meal_feedback) do
      add :group_id, :string
      add :meal_name, :string
      add :sentiment, :string
      add :raw_text, :string

      timestamps()
    end
  end
end
