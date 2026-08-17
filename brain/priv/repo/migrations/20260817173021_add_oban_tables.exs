defmodule Brain.Repo.Migrations.AddObanTables do
  use Ecto.Migration

  def up do
    Oban.Migrations.up()
  end

  def down do
    Oban.Migrations.down(version: 15)
  end
end
