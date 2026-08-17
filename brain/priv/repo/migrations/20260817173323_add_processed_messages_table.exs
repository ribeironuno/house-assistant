defmodule Brain.Repo.Migrations.AddProcessedMessagesTable do
  use Ecto.Migration

  def change do
    create table(:processed_messages, primary_key: false) do
      add :message_id, :string, primary_key: true
      add :processed_at, :utc_datetime, default: fragment("now()")
    end

    create index(:processed_messages, [:processed_at])
  end
end
