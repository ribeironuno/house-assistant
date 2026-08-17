defmodule Brain.ShoppingList do
  @moduledoc """
  Shopping-list context.

  Owns parsing, persistence, and Portuguese responses for shopping commands.

  Every item is scoped to the WhatsApp group that created it (`group_id`),
  so each group sees only its own list.
  """

  import Ecto.Query

  alias Brain.Repo
  alias Brain.ShoppingList.Item

  defp escape_ilike(term) do
    term
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  def add("", _group_id, _sender) do
    {:reply, "[BOT] Por favor especifica o item a adicionar, ex: 'adiciona leite'."}
  end

  def add(item_text, group_id, sender) do
    item_names = parse_items(item_text)

    if item_names == [] do
      {:reply, "[BOT] Por favor especifica o item a adicionar, ex: 'adiciona leite'."}
    else
      insert_items(item_names, group_id, sender)
    end
  end

  def remove("", _group_id) do
    {:reply, "[BOT] Por favor especifica o item a remover, ex: 'remove leite'."}
  end

  def remove(search_term, group_id) do
    cleaned = Brain.Text.strip_leading_articles(search_term)
    escaped = escape_ilike(cleaned)

    if cleaned == "" do
      {:reply, "[BOT] Por favor especifica o item a remover, ex: 'remove leite'."}
    else
      query =
        from(i in Item,
          where: i.done == false and i.group_id == ^group_id and ilike(i.name, ^"%#{escaped}%"),
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
  end

  def list(group_id) do
    query =
      from(i in Item,
        where: i.done == false and i.group_id == ^group_id,
        order_by: [asc: i.inserted_at]
      )

    items = Repo.all(query)

    if items == [] do
      {:reply, "[BOT] 🛒 A tua lista de compras está vazia."}
    else
      {:reply, "[BOT] 🛒 Lista de Compras:\n" <> format_numbered_items(items)}
    end
  end

  def clear(group_id) do
    from(i in Item, where: i.done == false and i.group_id == ^group_id)
    |> Repo.delete_all()

    {:reply, "[BOT] 🧹 Lista de compras limpa."}
  end

  def get_active_items(group_id) do
    from(i in Item,
      where: i.done == false and i.group_id == ^group_id,
      order_by: [asc: i.inserted_at]
    )
    |> Repo.all()
  end

  def delete_items(items) when is_list(items) do
    ids = Enum.map(items, & &1.id)

    from(i in Item, where: i.id in ^ids)
    |> Repo.delete_all()
  end

  defp parse_items(item_text) do
    item_text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp insert_items(item_names, group_id, sender) do
    multi =
      Enum.reduce(item_names, Ecto.Multi.new(), fn name, acc ->
        changeset = Item.changeset(%Item{}, %{name: name, added_by: sender, group_id: group_id})
        safe_key = String.replace(name, ~r/[^a-zA-Z0-9_]/, "_")
        Ecto.Multi.insert(acc, :"item_#{safe_key}", changeset)
      end)

    case Repo.transaction(multi) do
      {:ok, results} ->
        items = Enum.map(results, fn {_key, item} -> item end)
        # Preserve the original order from the input names
        ordered_items =
          Enum.flat_map(item_names, fn name ->
            Enum.filter(items, &(&1.name == name))
          end)

        {:reply, format_added_items(ordered_items)}

      {:error, _key, _result, _changes} ->
        {:reply, add_error_message(item_names)}
    end
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
