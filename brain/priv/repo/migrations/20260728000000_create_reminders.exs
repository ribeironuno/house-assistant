defmodule Brain.Repo.Migrations.CreateReminders do
  use Ecto.Migration

  def change do
    create table(:reminders) do
      add :text, :string, null: false
      add :group_id, :string, null: false
      add :created_by, :string
      add :remind_at, :utc_datetime, null: false
      add :sent_at, :utc_datetime

      timestamps()
    end

    create index(:reminders, [:sent_at, :remind_at])
  end
end
