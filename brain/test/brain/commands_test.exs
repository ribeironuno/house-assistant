defmodule Brain.CommandsTest do
  use BrainWeb.ConnCase, async: true
  alias Brain.Commands
  alias Brain.Repo
  alias Brain.ShoppingItem

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "adiciona command adds item to shopping list and returns confirmation" do
    assert {:reply, "[BOT] ✅ Adicionado: leite"} = Commands.handle("adiciona leite", "user_1")

    items = Repo.all(ShoppingItem)
    assert length(items) == 1
    assert hd(items).name == "leite"
    assert hd(items).added_by == "user_1"
    assert hd(items).done == false
  end

  test "adicionar command handles extra spaces and casing" do
    assert {:reply, "[BOT] ✅ Adicionado: Ovos Frescos"} = Commands.handle("  ADICIONAR   Ovos Frescos  ", "user_2")

    items = Repo.all(ShoppingItem)
    assert length(items) == 1
    assert hd(items).name == "Ovos Frescos"
  end

  test "add command without argument asks for item name" do
    assert {:reply, "[BOT] Por favor especifica o item a adicionar, ex: 'adiciona leite'."} = Commands.handle("adiciona", "user_1")
  end

  test "lista command shows items in order of insertion" do
    assert {:reply, "[BOT] 🛒 A tua lista de compras está vazia."} = Commands.handle("lista", "user_1")

    Commands.handle("adiciona leite", "user_1")
    Commands.handle("adiciona ovos", "user_2")

    expected_reply = "[BOT] 🛒 Lista de Compras:\n1. leite\n2. ovos"
    assert {:reply, ^expected_reply} = Commands.handle("lista", "user_1")
    assert {:reply, ^expected_reply} = Commands.handle("ver lista", "user_1")
  end

  test "remove command deletes matching item" do
    Commands.handle("adiciona leite", "user_1")
    Commands.handle("adiciona ovos", "user_1")

    assert {:reply, "[BOT] 🗑️ Removido: leite"} = Commands.handle("remove leite", "user_1")

    items = Repo.all(ShoppingItem)
    assert length(items) == 1
    assert hd(items).name == "ovos"
  end

  test "remover command handles case-insensitive substring match" do
    Commands.handle("adiciona Leite Gordo", "user_1")

    assert {:reply, "[BOT] 🗑️ Removido: Leite Gordo"} = Commands.handle("remover leite", "user_1")
    assert Repo.all(ShoppingItem) == []
  end

  test "remove command handles non-existent item gracefully" do
    assert {:reply, "[BOT] O item 'manteiga' não foi encontrado na lista de compras."} = Commands.handle("remove manteiga", "user_1")
  end

  test "limpar command deletes all shopping items" do
    Commands.handle("adiciona leite", "user_1")
    Commands.handle("adiciona ovos", "user_1")

    assert {:reply, "[BOT] 🧹 Lista de compras limpa."} = Commands.handle("limpar lista", "user_1")
    assert Repo.all(ShoppingItem) == []
  end

  test "unrecognized messages and bot response prefixes are ignored" do
    assert :ignore = Commands.handle("olá tudo bem?", "user_1")
    assert :ignore = Commands.handle("qual é a receita de hoje?", "user_1")
    assert :ignore = Commands.handle("[BOT] ✅ Adicionado: leite", "user_1")
    assert :ignore = Commands.handle("[BOT] 🗑️ Removido: leite", "user_1")
    assert :ignore = Commands.handle("[BOT] 🛒 Lista de Compras:\n1. leite", "user_1")
    assert :ignore = Commands.handle("[BOT] 🧹 Lista de compras limpa.", "user_1")
  end
end
