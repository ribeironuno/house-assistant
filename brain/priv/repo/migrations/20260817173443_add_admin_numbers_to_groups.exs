defmodule Brain.Repo.Migrations.AddAdminNumbersToGroups do
  use Ecto.Migration

  def change do
    alter table(:groups) do
      add :admin_numbers, {:array, :string}, default: []
    end
  end
end
