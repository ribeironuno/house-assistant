defmodule Brain.PantryTest do
  use BrainWeb.ConnCase, async: true
  import Ecto.Query

  alias Brain.Repo
  alias Brain.Pantry
  alias Brain.Pantry.Item

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "add_many adds multiple items to pantry" do
    assert {:reply, "[BOT] ✅ Adicionados à despensa:\n1. arroz\n2. frango\n3. atum"} =
             Pantry.add_many(["arroz", "frango", "atum"], "user_1")

    items = Repo.all(from(i in Item, order_by: [asc: i.inserted_at]))
    assert length(items) == 3
    assert Enum.map(items, & &1.name) == ["arroz", "frango", "atum"]
  end

  test "add_many with single item returns singular message" do
    assert {:reply, "[BOT] ✅ Adicionado à despensa: arroz"} =
             Pantry.add_many(["arroz"], "user_1")

    items = Repo.all(Item)
    assert length(items) == 1
    assert hd(items).name == "arroz"
    assert hd(items).added_by == "user_1"
  end

  test "add_many with empty list asks for items" do
    assert {:reply, "[BOT] Por favor especifica os itens, ex: 'tenho arroz, frango, atum'."} =
             Pantry.add_many([], "user_1")
  end

  test "remove deletes matching item by substring" do
    Pantry.add_many(["arroz", "frango"], "user_1")

    assert {:reply, "[BOT] 🗑️ Removido da despensa: arroz"} = Pantry.remove("arroz")

    items = Repo.all(Item)
    assert length(items) == 1
    assert hd(items).name == "frango"
  end

  test "remove handles case-insensitive match" do
    Pantry.add_many(["Arroz Integral"], "user_1")

    assert {:reply, "[BOT] 🗑️ Removido da despensa: Arroz Integral"} = Pantry.remove("arroz")
    assert Repo.all(Item) == []
  end

  test "remove with non-existent item returns error" do
    assert {:reply, "[BOT] O item 'peixe' não foi encontrado na despensa."} =
             Pantry.remove("peixe")
  end

  test "remove with empty string asks for item" do
    assert {:reply, "[BOT] Por favor especifica o item a remover, ex: 'usei arroz'."} =
             Pantry.remove("")
  end

  test "list returns all pantry items" do
    Pantry.add_many(["arroz", "frango"], "user_1")

    assert {:reply, "[BOT] 🏠 Despensa:\n1. arroz\n2. frango"} = Pantry.list()
  end

  test "list with empty pantry returns empty message" do
    assert {:reply, "[BOT] 🏠 A despensa está vazia."} = Pantry.list()
  end

  test "clear removes all items" do
    Pantry.add_many(["arroz", "frango", "atum"], "user_1")

    assert {:reply, "[BOT] 🧹 Despensa limpa."} = Pantry.clear()
    assert Repo.all(Item) == []
  end

  test "get_all returns items ordered by insertion" do
    Pantry.add_many(["atum", "arroz", "frango"], "user_1")

    items = Pantry.get_all()
    assert Enum.map(items, & &1.name) == ["atum", "arroz", "frango"]
  end
end
