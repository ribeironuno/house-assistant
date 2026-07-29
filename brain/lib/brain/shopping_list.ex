defmodule Brain.ShoppingList do
  @moduledoc """
  Shopping-list context.

  Owns parsing, persistence, and Portuguese responses for shopping commands.
  """

  import Ecto.Query

  alias Brain.Repo
  alias Brain.ShoppingList.Item

  def add("", _sender) do
    {:reply, "[BOT] Por favor especifica o item a adicionar, ex: 'adiciona leite'."}
  end

  def add(item_text, sender) do
    item_names = parse_items(item_text)

    if item_names == [] do
      {:reply, "[BOT] Por favor especifica o item a adicionar, ex: 'adiciona leite'."}
    else
      insert_items(item_names, sender)
    end
  end

  def remove("") do
    {:reply, "[BOT] Por favor especifica o item a remover, ex: 'remove leite'."}
  end

  def remove(search_term) do
    query =
      from(i in Item,
        where: i.done == false and ilike(i.name, ^"%#{search_term}%"),
        order_by: [desc: i.inserted_at],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        {:reply, "[BOT] O item '#{search_term}' não foi encontrado na lista de compras."}

      item ->
        Repo.delete!(item)
        {:reply, "[BOT] 🗑️ Removido: #{item.name}"}
    end
  end

  def list do
    query =
      from(i in Item,
        where: i.done == false,
        order_by: [asc: i.inserted_at]
      )

    items = Repo.all(query)

    if items == [] do
      {:reply, "[BOT] 🛒 A tua lista de compras está vazia."}
    else
      {:reply, "[BOT] 🛒 Lista de Compras:\n" <> format_numbered_items(items)}
    end
  end

  def clear do
    from(i in Item, where: i.done == false)
    |> Repo.delete_all()

    {:reply, "[BOT] 🧹 Lista de compras limpa."}
  end

  defp parse_items(item_text) do
    item_text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp insert_items(item_names, sender) do
    inserted_items =
      Enum.map(item_names, fn name ->
        changeset = Item.changeset(%Item{}, %{name: name, added_by: sender})
        Repo.insert(changeset)
      end)

    if Enum.all?(inserted_items, &match?({:ok, _item}, &1)) do
      items = Enum.map(inserted_items, fn {:ok, item} -> item end)
      {:reply, format_added_items(items)}
    else
      rollback_inserted_items(inserted_items)
      {:reply, add_error_message(item_names)}
    end
  end

  defp rollback_inserted_items(inserted_items) do
    Repo.transaction(fn ->
      Enum.each(inserted_items, fn
        {:ok, item} -> Repo.delete(item)
        {:error, _changeset} -> :ok
      end)
    end)
  end

  defp add_error_message([_item]),
    do: "[BOT] Não foi possível adicionar o item à lista de compras."

  defp add_error_message(_items),
    do: "[BOT] Não foi possível adicionar os itens à lista de compras."

  defp format_added_items([item]) do
    "[BOT] ✅ Adicionado: #{item.name}"
  end

  defp format_added_items(items) do
    "[BOT] ✅ Adicionados:\n" <> format_numbered_items(items)
  end

  defp format_numbered_items(items) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {item, idx} -> "#{idx}. #{item.name}" end)
    |> Enum.join("\n")
  end
end
