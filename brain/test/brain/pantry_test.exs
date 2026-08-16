defmodule Brain.PantryTest do
  use BrainWeb.ConnCase, async: true
  import Ecto.Query

  alias Brain.Repo
  alias Brain.Pantry
  alias Brain.Pantry.Item

  @group_id "group_1"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    ensure_group(@group_id)
  end

  test "add_many adds multiple items to pantry" do
    assert {:reply, "[BOT] ✅ Adicionados à despensa:\n1. arroz\n2. frango\n3. atum"} =
             Pantry.add_many(["arroz", "frango", "atum"], @group_id, "user_1")

    items = Repo.all(from(i in Item, order_by: [asc: i.inserted_at]))
    assert length(items) == 3
    assert Enum.map(items, & &1.name) == ["arroz", "frango", "atum"]
  end

  test "add_many with single item returns singular message" do
    assert {:reply, "[BOT] ✅ Adicionado à despensa: arroz"} =
             Pantry.add_many(["arroz"], @group_id, "user_1")

    items = Repo.all(Item)
    assert length(items) == 1
    assert hd(items).name == "arroz"
    assert hd(items).added_by == "user_1"
  end

  test "add_many with empty list asks for items" do
    assert {:reply, "[BOT] Por favor especifica os itens, ex: 'tenho arroz, frango, atum'."} =
             Pantry.add_many([], @group_id, "user_1")
  end

  test "remove deletes matching item by substring" do
    Pantry.add_many(["arroz", "frango"], @group_id, "user_1")

    assert {:reply, "[BOT] 🗑️ Removido da despensa: arroz"} = Pantry.remove("arroz", @group_id)

    items = Repo.all(Item)
    assert length(items) == 1
    assert hd(items).name == "frango"
  end

  test "remove handles case-insensitive match" do
    Pantry.add_many(["Arroz Integral"], @group_id, "user_1")

    assert {:reply, "[BOT] 🗑️ Removido da despensa: Arroz Integral"} =
             Pantry.remove("arroz", @group_id)

    assert Repo.all(Item) == []
  end

  test "remove with non-existent item returns error" do
    assert {:reply, "[BOT] O item 'peixe' não foi encontrado na despensa."} =
             Pantry.remove("peixe", @group_id)
  end

  test "remove with empty string asks for item" do
    assert {:reply, "[BOT] Por favor especifica o item a remover, ex: 'usei arroz'."} =
             Pantry.remove("", @group_id)
  end

  test "list returns all pantry items" do
    Pantry.add_many(["arroz", "frango"], @group_id, "user_1")

    assert {:reply, "[BOT] 🏠 Despensa:\n1. arroz\n2. frango"} = Pantry.list(@group_id)
  end

  test "list with empty pantry returns empty message" do
    assert {:reply, "[BOT] 🏠 A despensa está vazia."} = Pantry.list(@group_id)
  end

  test "clear removes all items" do
    Pantry.add_many(["arroz", "frango", "atum"], @group_id, "user_1")

    assert {:reply, "[BOT] 🧹 Despensa limpa."} = Pantry.clear(@group_id)
    assert Repo.all(Item) == []
  end

  test "get_all returns items ordered by insertion" do
    Pantry.add_many(["atum", "arroz", "frango"], @group_id, "user_1")

    items = Pantry.get_all(@group_id)
    assert Enum.map(items, & &1.name) == ["atum", "arroz", "frango"]
  end
end
