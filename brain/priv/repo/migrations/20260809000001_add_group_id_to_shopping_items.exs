defmodule Brain.Repo.Migrations.AddGroupIdToShoppingItems do
  use Ecto.Migration

  def change do
    alter table(:shopping_items) do
      add :group_id, :string
    end

    create index(:shopping_items, [:group_id])
  end
end
