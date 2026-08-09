defmodule Brain.Repo.Migrations.AddGroupIdToPantryItems do
  use Ecto.Migration

  def change do
    alter table(:pantry_items) do
      add :group_id, :string
    end

    create index(:pantry_items, [:group_id])
  end
end
