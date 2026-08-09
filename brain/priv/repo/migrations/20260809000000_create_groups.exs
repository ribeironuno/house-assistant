defmodule Brain.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups, primary_key: false) do
      add :group_id, :string, primary_key: true
      add :status, :string, null: false, default: "pending"

      timestamps()
    end
  end
end
