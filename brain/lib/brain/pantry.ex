defmodule Brain.Pantry do
  @moduledoc """
  Pantry context.

  Owns persistence and Portuguese responses for pantry commands.
  """

  import Ecto.Query

  alias Brain.Repo
  alias Brain.Pantry.Item

  def add_many([], _added_by) do
    {:reply, "[BOT] Por favor especifica os itens, ex: 'tenho arroz, frango, atum'."}
  end

  def add_many(names, added_by) when is_list(names) do
    case add_many_models(names, added_by) do
      {:ok, items} -> {:reply, format_added_items(items)}
      {:error, _} -> {:reply, "[BOT] Não foi possível adicionar os itens à despensa."}
    end
  end

  @doc """
  Inserts multiple pantry items, returning the inserted structs.
  Rolls back all inserts if any fails. Returns `{:ok, items}` or `{:error, :insert_failed}`.
  """
  def add_many_models(names, added_by) when is_list(names) do
    inserted_items =
      Enum.map(names, fn name ->
        changeset = Item.changeset(%Item{}, %{name: name, added_by: added_by})
        Repo.insert(changeset)
      end)

    if Enum.all?(inserted_items, &match?({:ok, _item}, &1)) do
      {:ok, Enum.map(inserted_items, fn {:ok, item} -> item end)}
    else
      rollback_inserted_items(inserted_items)
      {:error, :insert_failed}
    end
  end

  def remove("") do
    {:reply, "[BOT] Por favor especifica o item a remover, ex: 'usei arroz'."}
  end

  def remove(search_term) do
    query =
      from(i in Item,
        where: ilike(i.name, ^"%#{search_term}%"),
        order_by: [desc: i.inserted_at],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        {:reply, "[BOT] O item '#{search_term}' não foi encontrado na despensa."}

      item ->
        Repo.delete!(item)
        {:reply, "[BOT] 🗑️ Removido da despensa: #{item.name}"}
    end
  end

  def list do
    items = Repo.all(from(i in Item, order_by: [asc: i.inserted_at]))

    if items == [] do
      {:reply, "[BOT] 🏠 A despensa está vazia."}
    else
      {:reply, "[BOT] 🏠 Despensa:\n" <> format_numbered_items(items)}
    end
  end

  def clear do
    Repo.delete_all(Item)
    {:reply, "[BOT] 🧹 Despensa limpa."}
  end

  def get_all do
    Repo.all(from(i in Item, order_by: [asc: i.inserted_at]))
  end

  defp rollback_inserted_items(inserted_items) do
    Repo.transaction(fn ->
      Enum.each(inserted_items, fn
        {:ok, item} -> Repo.delete(item)
        {:error, _changeset} -> :ok
      end)
    end)
  end

  defp format_added_items([item]) do
    "[BOT] ✅ Adicionado à despensa: #{item.name}"
  end

  defp format_added_items(items) do
    "[BOT] ✅ Adicionados à despensa:\n" <> format_numbered_items(items)
  end

  defp format_numbered_items(items) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {item, idx} -> "#{idx}. #{item.name}" end)
    |> Enum.join("\n")
  end
end
