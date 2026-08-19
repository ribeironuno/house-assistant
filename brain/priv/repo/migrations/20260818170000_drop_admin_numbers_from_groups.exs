defmodule Brain.Repo.Migrations.DropAdminNumbersFromGroups do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE groups DROP COLUMN IF EXISTS admin_numbers"
  end

  def down do
    alter table(:groups) do
      add :admin_numbers, {:array, :string}, default: []
    end
  end
end
