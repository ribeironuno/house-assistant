defmodule Brain.Menu.WeeklyMenu do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema for weekly menus.
  """

  schema "weekly_menus" do
    field(:group_id, :string)
    field(:constraints_raw, :string)
    field(:meals, :map)
    field(:generated_at, :utc_datetime)

    timestamps()
  end

  def changeset(weekly_menu, attrs) do
    weekly_menu
    |> cast(attrs, [:group_id, :constraints_raw, :meals, :generated_at])
    |> validate_required([:group_id, :meals])
    |> foreign_key_constraint(:group_id)
  end
end
