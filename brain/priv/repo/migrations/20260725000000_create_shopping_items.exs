defmodule Brain.Repo.Migrations.CreateShoppingItems do
  use Ecto.Migration

  def change do
    create table(:shopping_items) do
      add :name, :string, null: false
      add :added_by, :string
      add :done, :boolean, default: false, null: false

      timestamps()
    end
  end
end
