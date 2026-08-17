defmodule Brain.Repo.Migrations.AddGroupNameAndNewStatuses do
  use Ecto.Migration

  def change do
    alter table(:groups, primary_key: false) do
      add(:name, :string)
    end
  end
end
