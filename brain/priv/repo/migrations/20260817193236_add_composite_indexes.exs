defmodule Brain.Repo.Migrations.AddCompositeIndexes do
  use Ecto.Migration

  def change do
    create index(:shopping_items, [:group_id, :done])
    create index(:weekly_menus, [:group_id, :inserted_at])
  end
end
