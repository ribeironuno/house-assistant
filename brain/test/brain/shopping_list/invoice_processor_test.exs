defmodule Brain.ShoppingList.InvoiceProcessorTest do
  use BrainWeb.ConnCase, async: false
  import Ecto.Query

  alias Brain.LLM.Providers.TestStub
  alias Brain.Pantry
  alias Brain.Pantry.Item, as: PantryItem
  alias Brain.Repo
  alias Brain.ShoppingList
  alias Brain.ShoppingList.InvoiceProcessor
  alias Brain.ShoppingList.Item

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    on_exit(fn -> TestStub.reset() end)
  end

  test "match_and_remove matches receipt items against DB and removes them" do
    ShoppingList.add("leite, ovos, manteiga", "user_1")

    purchased_items = ["leite", "ovos", "pão de forma"]

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(purchased_items)

    assert reply =~ "[BOT] 🧾 Fatura processada!"
    assert reply =~ "• leite"
    assert reply =~ "• ovos"
    assert reply =~ "(Outros itens na fatura: pão de forma)"

    remaining = Repo.all(Item)
    assert length(remaining) == 1
    assert hd(remaining).name == "manteiga"
  end

  test "match_and_remove does NOT delete items for different products (no false positives)" do
    ShoppingList.add("leite, arroz, salada", "user_1")

    purchased_items = ["leite de coco", "arroz de marisco", "sal"]

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(purchased_items)

    assert reply =~ "nenhum dos produtos comprados estava na tua lista de compras"

    remaining = Repo.all(Item)
    assert length(remaining) == 3
  end

  test "match_and_remove enforces 1:1 — one receipt item deletes at most one list item" do
    ShoppingList.add("leite, leite magro, manteiga", "user_1")

    purchased_items = ["leite"]

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(purchased_items)

    remaining = Repo.all(Item)
    assert length(remaining) == 2
    refute Enum.any?(remaining, &(&1.name == "leite"))
    assert Enum.any?(remaining, &(&1.name == "leite magro"))
  end

  test "match_and_remove uses LLM semantic matching for descriptor-heavy receipt names" do
    ShoppingList.add("leite, piripiri", "user_1")

    TestStub.set_response(
      {:ok,
       %{
         "matches" => [
           %{"list_item" => "leite", "receipt_item" => "leite meio gordo mimosa"},
           %{"list_item" => "piripiri", "receipt_item" => "tabasco"}
         ]
       }}
    )

    purchased_items = ["leite meio gordo mimosa", "tabasco"]

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(purchased_items)

    assert reply =~ "• leite"
    assert reply =~ "• piripiri"

    remaining = Repo.all(Item)
    assert remaining == []
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

  test "match_and_remove adds purchased items to the pantry" do
    ShoppingList.add("leite", "user_1")

    purchased_items = ["leite", "pão de forma"]

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(purchased_items, "user_1")

    assert reply =~ "🏠 Adicionados à despensa:"
    assert reply =~ "• leite"
    assert reply =~ "• pão de forma"

    pantry_items = Repo.all(from(p in PantryItem, order_by: [asc: p.inserted_at]))
    assert Enum.map(pantry_items, & &1.name) == ["leite", "pão de forma"]
    assert Enum.all?(pantry_items, &(&1.added_by == "user_1"))
  end

  test "match_and_remove adds items to pantry even when shopping list is empty" do
    purchased_items = ["arroz"]

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(purchased_items, "user_2")

    assert reply =~ "lista de compras estava vazia"
    assert reply =~ "🏠 Adicionados à despensa:"

    assert Repo.all(PantryItem) |> Enum.map(& &1.name) == ["arroz"]
    assert hd(Repo.all(PantryItem)).added_by == "user_2"
  end

  test "match_and_remove does not duplicate items already in the pantry" do
    Pantry.add_many(["leite"], "user_1")
    ShoppingList.add("leite", "user_1")

    assert {:reply, reply} = InvoiceProcessor.match_and_remove(["leite"], "user_1")

    refute reply =~ "🏠 Adicionados à despensa:"
    assert length(Repo.all(PantryItem)) == 1
  end

  test "find_matches matches via LLM semantic matching when names carry descriptors" do
    items = [
      %Item{id: 1, name: "leite"},
      %Item{id: 2, name: "ovos frescos"},
      %Item{id: 3, name: "arroz"}
    ]

    receipt = ["LEITE MEIO GORDO UHT 1L", "ovos", "chocolates"]

    TestStub.set_response(
      {:ok,
       %{
         "matches" => [
           %{"list_item" => "leite", "receipt_item" => "LEITE MEIO GORDO UHT 1L"},
           %{"list_item" => "ovos frescos", "receipt_item" => "ovos"}
         ]
       }}
    )

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

  test "find_matches uses LLM to match semantically different item pairs" do
    TestStub.set_response(
      {:ok, %{"matches" => [%{"list_item" => "piripiri", "receipt_item" => "tabasco chipotle"}]}}
    )

    items = [
      %Item{id: 1, name: "leite"},
      %Item{id: 2, name: "piripiri"}
    ]

    receipt = ["leite", "tabasco chipotle"]

    {matched, unmatched} = InvoiceProcessor.find_matches(items, receipt)

    assert Enum.map(matched, & &1.name) == ["leite", "piripiri"]
    assert unmatched == []
  end

  test "find_matches accepts receipt_item with different case and removes it from unmatched" do
    TestStub.set_response(
      {:ok, %{"matches" => [%{"list_item" => "piripiri", "receipt_item" => "Tabasco Chipotle"}]}}
    )

    items = [%Item{id: 1, name: "piripiri"}]
    receipt = ["tabasco chipotle"]

    {matched, unmatched} = InvoiceProcessor.find_matches(items, receipt)

    assert Enum.map(matched, & &1.name) == ["piripiri"]
    assert unmatched == []
  end

  test "find_matches rejects LLM pairs whose receipt_item is not on the receipt" do
    TestStub.set_response(
      {:ok, %{"matches" => [%{"list_item" => "piripiri", "receipt_item" => "sriracha"}]}}
    )

    items = [%Item{id: 1, name: "piripiri"}]
    receipt = ["tabasco chipotle"]

    {matched, unmatched} = InvoiceProcessor.find_matches(items, receipt)

    assert Enum.map(matched, & &1.name) == []
    assert unmatched == ["tabasco chipotle"]
  end

  test "find_matches does not consult LLM when receipt side is empty" do
    TestStub.set_response(
      {:ok, %{"matches" => [%{"list_item" => "piripiri", "receipt_item" => "tabasco"}]}}
    )

    items = [%Item{id: 1, name: "leite"}, %Item{id: 2, name: "piripiri"}]
    receipt = ["leite"]

    {matched, unmatched} = InvoiceProcessor.find_matches(items, receipt)

    assert Enum.map(matched, & &1.name) == ["leite"]
    assert unmatched == []
  end

  test "find_matches does not consult LLM when db side is empty" do
    TestStub.set_response(
      {:ok, %{"matches" => [%{"list_item" => "leite", "receipt_item" => "tabasco"}]}}
    )

    items = [%Item{id: 1, name: "leite"}]
    receipt = ["leite", "tabasco chipotle"]

    {matched, unmatched} = InvoiceProcessor.find_matches(items, receipt)

    assert Enum.map(matched, & &1.name) == ["leite"]
    assert unmatched == ["tabasco chipotle"]
  end

  test "find_matches degrades gracefully on malformed LLM response" do
    TestStub.set_response({:ok, %{"matches" => ["piripiri"]}})

    items = [%Item{id: 1, name: "leite"}, %Item{id: 2, name: "piripiri"}]
    receipt = ["leite", "tabasco chipotle"]

    {matched, unmatched} = InvoiceProcessor.find_matches(items, receipt)

    assert Enum.map(matched, & &1.name) == ["leite"]
    assert unmatched == ["tabasco chipotle"]
  end
end
