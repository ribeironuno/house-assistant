defmodule Brain.ShoppingList.ItemTest do
  use BrainWeb.ConnCase, async: true

  alias Brain.ShoppingList.Item

  test "changeset requires group_id" do
    changeset = Item.changeset(%Item{}, %{name: "leite"})

    assert {"can't be blank", _} = changeset.errors[:group_id]
  end

  test "changeset is valid with name and group_id" do
    changeset = Item.changeset(%Item{}, %{name: "leite", group_id: "group_1"})

    assert changeset.valid?
  end
end
