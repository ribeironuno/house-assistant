defmodule Brain.GroupIsolationTest do
  use BrainWeb.ConnCase, async: true

  alias Brain.Repo
  alias Brain.Pantry
  alias Brain.ShoppingList
  alias Brain.ShoppingList.InvoiceProcessor

  @group_a "group_a"
  @group_b "group_b"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    ensure_group(@group_a)
    ensure_group(@group_b)
  end

  test "shopping list items are isolated per group" do
    ShoppingList.add("leite", @group_a, "user_a")
    ShoppingList.add("pão", @group_b, "user_b")

    assert Enum.map(ShoppingList.get_active_items(@group_a), & &1.name) == ["leite"]
    assert Enum.map(ShoppingList.get_active_items(@group_b), & &1.name) == ["pão"]
  end

  test "shopping list remove only touches its own group" do
    ShoppingList.add("leite", @group_a, "user_a")
    ShoppingList.add("leite", @group_b, "user_b")

    assert {:reply, "[BOT] 🗑️ Removido: leite"} = ShoppingList.remove("leite", @group_a)

    assert Enum.map(ShoppingList.get_active_items(@group_a), & &1.name) == []
    assert Enum.map(ShoppingList.get_active_items(@group_b), & &1.name) == ["leite"]
  end

  test "shopping list clear only clears its own group" do
    ShoppingList.add("leite", @group_a, "user_a")
    ShoppingList.add("pão", @group_b, "user_b")

    ShoppingList.clear(@group_a)

    assert ShoppingList.get_active_items(@group_a) == []
    assert Enum.map(ShoppingList.get_active_items(@group_b), & &1.name) == ["pão"]
  end

  test "pantry items are isolated per group" do
    Pantry.add_many(["arroz"], @group_a, "user_a")
    Pantry.add_many(["atum"], @group_b, "user_b")

    assert Enum.map(Pantry.get_all(@group_a), & &1.name) == ["arroz"]
    assert Enum.map(Pantry.get_all(@group_b), & &1.name) == ["atum"]
  end

  test "invoice matching does not remove other groups' shopping list items" do
    ShoppingList.add("leite", @group_a, "user_a")
    ShoppingList.add("pão", @group_b, "user_b")

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(["leite"], @group_b, "user_b")
    assert reply =~ "nenhum dos produtos comprados estava na tua lista"

    assert Enum.map(ShoppingList.get_active_items(@group_a), & &1.name) == ["leite"]
  end

  test "invoice processing adds purchased items to the pantry of the matching group only" do
    ShoppingList.add("leite", @group_a, "user_a")

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(["leite"], @group_a, "user_a")
    assert reply =~ "Adicionados à despensa"

    assert Enum.map(Pantry.get_all(@group_a), & &1.name) == ["leite"]
    assert Pantry.get_all(@group_b) == []
  end
end
