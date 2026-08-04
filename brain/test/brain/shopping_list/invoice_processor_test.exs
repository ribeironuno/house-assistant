defmodule Brain.ShoppingList.InvoiceProcessorTest do
  use BrainWeb.ConnCase, async: true

  alias Brain.Repo
  alias Brain.ShoppingList
  alias Brain.ShoppingList.InvoiceProcessor
  alias Brain.ShoppingList.Item

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "match_and_remove matches receipt items against DB and removes them" do
    ShoppingList.add("leite, ovos, manteiga", "user_1")

    purchased_items = ["leite meio gordo mimosa", "ovos de galinha", "pão de forma"]

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(purchased_items)

    assert reply =~ "[BOT] 🧾 Fatura processada!"
    assert reply =~ "• leite"
    assert reply =~ "• ovos"
    assert reply =~ "(Outros itens na fatura: pão de forma)"

    remaining = Repo.all(Item)
    assert length(remaining) == 1
    assert hd(remaining).name == "manteiga"
  end

  test "match_and_remove when DB list is empty" do
    purchased_items = ["leite", "pão"]

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(purchased_items)

    assert reply =~ "[BOT] 🧾 Fatura lida com sucesso!"
    assert reply =~ "lista de compras estava vazia"
    assert reply =~ "• leite"
    assert reply =~ "• pão"
  end

  test "match_and_remove when no items match" do
    ShoppingList.add("sabão", "user_1")
    purchased_items = ["leite", "pão"]

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(purchased_items)

    assert reply =~ "nenhum dos produtos comprados estava na tua lista"
    assert length(Repo.all(Item)) == 1
  end

  test "find_matches correctly matches normalized strings" do
    items = [
      %Item{id: 1, name: "leite"},
      %Item{id: 2, name: "ovos frescos"},
      %Item{id: 3, name: "arroz"}
    ]

    receipt = ["LEITE MEIO GORDO UHT 1L", "ovos", "chocolates"]

    {matched, unmatched} = InvoiceProcessor.find_matches(items, receipt)

    assert Enum.map(matched, & &1.name) == ["leite", "ovos frescos"]
    assert unmatched == ["chocolates"]
  end

  test "llm_semantic_match degrades to :error when provider fails" do
    items = [%Item{id: 1, name: "piripiri"}]
    receipt = ["tabasco chipotle"]

    assert InvoiceProcessor.llm_semantic_match(items, receipt) == :error
  end

  test "find_matches falls back to string-only matches when LLM errors" do
    items = [
      %Item{id: 1, name: "leite"},
      %Item{id: 2, name: "piripiri"}
    ]

    receipt = ["leite", "tabasco chipotle"]

    {matched, unmatched} = InvoiceProcessor.find_matches(items, receipt)

    assert Enum.map(matched, & &1.name) == ["leite"]
    assert unmatched == ["tabasco chipotle"]
  end
end
