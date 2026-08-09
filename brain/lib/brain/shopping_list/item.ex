defmodule Brain.ShoppingList.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema for a shopping list item.

  ## Fields

  - `:name`      — the item name (required, trimmed on insert)
  - `:added_by`  — WhatsApp JID of the person who added it
  - `:group_id`  — WhatsApp group JID this item belongs to
  - `:done`      — whether the item has been purchased (default: false)

  Items with `done: false` are considered active and shown in list/remove commands.
  """

  schema "shopping_items" do
    field(:name, :string)
    field(:added_by, :string)
    field(:group_id, :string)
    field(:done, :boolean, default: false)

    timestamps()
  end

  @doc """
  Builds a changeset for a shopping item.
  """
  def changeset(shopping_item, attrs) do
    shopping_item
    |> cast(attrs, [:name, :added_by, :group_id, :done])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> update_change(:name, &String.trim/1)
  end
end
