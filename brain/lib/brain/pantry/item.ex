defmodule Brain.Pantry.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema for a pantry item.

  ## Fields

  - `:name`      — the item name (required, trimmed on insert)
  - `:added_by`  — WhatsApp JID of the person who added it
  """

  schema "pantry_items" do
    field(:name, :string)
    field(:added_by, :string)

    timestamps()
  end

  def changeset(pantry_item, attrs) do
    pantry_item
    |> cast(attrs, [:name, :added_by])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> update_change(:name, &String.trim/1)
  end
end
