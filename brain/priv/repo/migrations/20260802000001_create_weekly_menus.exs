defmodule Brain.Repo.Migrations.CreateWeeklyMenus do
  use Ecto.Migration

  def change do
    create table(:weekly_menus) do
      add :group_id, :string
      add :constraints_raw, :string
      add :meals, :map
      add :generated_at, :utc_datetime

      timestamps()
    end
  end
end
