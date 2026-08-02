defmodule Brain.Repo.Migrations.CreatePantryItems do
  use Ecto.Migration

  def change do
    create table(:pantry_items) do
      add :name, :string, null: false
      add :added_by, :string

      timestamps()
    end
  end
end
