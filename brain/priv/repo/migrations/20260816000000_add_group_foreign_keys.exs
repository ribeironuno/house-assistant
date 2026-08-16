defmodule Brain.Repo.Migrations.AddGroupForeignKeyConstraints do
  use Ecto.Migration

  def up do
    # Remove rows whose group_id does not reference a real group (including
    # legacy NULL-group rows) so the FK constraints below can be enforced.
    delete_orphans("shopping_items")
    delete_orphans("pantry_items")
    delete_orphans("reminders")
    delete_orphans("weekly_menus")
    delete_orphans("meal_feedback")

    alter table(:shopping_items) do
      modify :group_id,
             references(:groups, column: :group_id, type: :string, on_delete: :delete_all),
             from: :string,
             null: false
    end

    alter table(:pantry_items) do
      modify :group_id,
             references(:groups, column: :group_id, type: :string, on_delete: :delete_all),
             from: :string,
             null: false
    end

    alter table(:reminders) do
      modify :group_id,
             references(:groups, column: :group_id, type: :string, on_delete: :delete_all),
             from: :string
    end

    alter table(:weekly_menus) do
      modify :group_id,
             references(:groups, column: :group_id, type: :string, on_delete: :delete_all),
             from: :string,
             null: false
    end

    alter table(:meal_feedback) do
      modify :group_id,
             references(:groups, column: :group_id, type: :string, on_delete: :delete_all),
             from: :string,
             null: false
    end

    create index(:reminders, [:group_id])
    create index(:weekly_menus, [:group_id])
    create index(:meal_feedback, [:group_id])
  end

  def down do
    drop index(:meal_feedback, [:group_id])
    drop index(:weekly_menus, [:group_id])
    drop index(:reminders, [:group_id])

    alter table(:meal_feedback), do: modify(:group_id, :string, null: true)
    alter table(:weekly_menus), do: modify(:group_id, :string, null: true)
    alter table(:reminders), do: modify(:group_id, :string)
    alter table(:pantry_items), do: modify(:group_id, :string, null: true)
    alter table(:shopping_items), do: modify(:group_id, :string, null: true)
  end

  defp delete_orphans(table) do
    execute("""
    DELETE FROM #{table}
    WHERE group_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM groups g WHERE g.group_id = #{table}.group_id)
    """)
  end
end
