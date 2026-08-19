defmodule Brain.Pantry do
  @moduledoc """
  Pantry context.

  Owns persistence and Portuguese responses for pantry commands.
  """

  import Ecto.Query

  alias Brain.Repo
  alias Brain.Pantry.Item

  defp escape_ilike(term) do
    term
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  def add_many([], _group_id, _added_by) do
    {:reply, "[BOT] Por favor especifica os itens, ex: 'tenho arroz, frango, atum'."}
  end

  def add_many(names, group_id, added_by) when is_list(names) do
    case add_many_models(names, group_id, added_by) do
      {:ok, items} -> {:reply, format_added_items(items)}
      {:error, _} -> {:reply, "[BOT] Não foi possível adicionar os itens à despensa."}
    end
  end

  def add_many_models(names, group_id, added_by) when is_list(names) do
    existing_names =
      names
      |> Enum.uniq()
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> existing_names_for_group(group_id)

    new_names = names |> Enum.uniq() |> Enum.reject(&(&1 in existing_names or String.trim(&1) == ""))

    if new_names == [] do
      {:ok, []}
    else
      multi =
        Enum.reduce(new_names, Ecto.Multi.new(), fn name, acc ->
          changeset = Item.changeset(%Item{}, %{name: name, added_by: added_by, group_id: group_id})
          safe_key = String.replace(name, ~r/[^a-zA-Z0-9_]/, "_")
          Ecto.Multi.insert(acc, :"item_#{safe_key}", changeset)
        end)

      case Repo.transaction(multi) do
        {:ok, results} ->
          items = Enum.map(results, fn {_key, item} -> item end)
          ordered_items =
            Enum.flat_map(new_names, fn name ->
              Enum.filter(items, &(&1.name == name))
            end)

          {:ok, ordered_items}

        {:error, _key, _result, _changes} ->
          {:error, :insert_failed}
      end
    end
  end

  defp existing_names_for_group([], _group_id), do: []

  defp existing_names_for_group(names, group_id) do
    trimmed = Enum.map(names, &String.trim/1)

    existing =
      Repo.all(
        from(i in Item,
          where: i.group_id == ^group_id and i.name in ^trimmed,
          select: i.name
        )
      )

    MapSet.to_list(MapSet.new(existing))
  end

  def remove("", _group_id) do
    {:reply, "[BOT] Por favor especifica o item a remover, ex: 'usei arroz'."}
  end

  def remove(search_term, group_id) do
    cleaned = Brain.Text.strip_leading_articles(search_term)
    escaped = escape_ilike(cleaned)

    if cleaned == "" do
      {:reply, "[BOT] Por favor especifica o item a remover, ex: 'usei arroz'."}
    else
      query =
        from(i in Item,
          where: i.group_id == ^group_id and ilike(i.name, ^"%#{escaped}%"),
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
  end

  def list(group_id) do
    items =
      Repo.all(from(i in Item, where: i.group_id == ^group_id, order_by: [asc: i.inserted_at]))

    if items == [] do
      {:reply, "[BOT] 🏠 A despensa está vazia."}
    else
      {:reply, "[BOT] 🏠 Despensa:\n" <> format_numbered_items(items)}
    end
  end

  def clear(group_id) do
    from(i in Item, where: i.group_id == ^group_id)
    |> Repo.delete_all()

    {:reply, "[BOT] 🧹 Despensa limpa."}
  end

  def get_all(group_id) do
    Repo.all(from(i in Item, where: i.group_id == ^group_id, order_by: [asc: i.inserted_at]))
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
