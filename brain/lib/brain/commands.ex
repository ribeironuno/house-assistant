defmodule Brain.Commands do
  @moduledoc """
  Isolated command parser and executor for the shopping list.

  All commands and responses are in Portuguese. This module is intentionally
  kept free of HTTP or WhatsApp concerns so it can be tested in isolation and
  replaced with an LLM-based parser in a future phase.

  ## Supported commands (case-insensitive)

  | Input                             | Action                        |
  |-----------------------------------|-------------------------------|
  | `adiciona <item>` / `adicionar`   | Add item to the shopping list |
  | `remove <item>` / `remover`       | Remove item by substring match|
  | `lista` / `ver lista` / `mostrar lista` | Show active items       |
  | `limpar` / `limpar lista`         | Clear all active items        |

  ## Return values

  - `{:reply, text}` — a response string to be sent back to the WhatsApp group.
    All reply strings are prefixed with `[BOT]` so the bridge can identify and
    discard the echo event it receives when the same WhatsApp account is used
    for both the bot and the owner's phone.
  - `:ignore` — the message is unrecognised or is a bot echo; no reply is sent.

  ## Loop prevention

  Any message whose downcased text starts with `[bot]` is immediately returned
  as `:ignore`. This prevents the brain from reacting to its own replies if
  they somehow bypass the bridge-level filter.
  """

  @doc """
  Ponto de entrada principal para analisar e executar comandos de texto.

  Retorna `{:reply, texto_resposta}` ou `:ignore`.
  """

  import Ecto.Query
  alias Brain.Repo
  alias Brain.ShoppingItem

  def handle(text, sender) when is_binary(text) do
    trimmed_raw = String.trim(text)
    trimmed_lower = String.downcase(trimmed_raw)

    if String.starts_with?(trimmed_lower, ["[bot]", "✅", "🗑️", "🛒", "🧹", "por favor", "o item", "não foi"]) do
      :ignore
    else
      cond do
        trimmed_lower in ["lista", "mostrar lista", "ver lista", "list", "show list"] ->
          handle_list()

        trimmed_lower in ["limpar", "limpar lista", "clear", "clear list"] ->
          handle_clear()

        String.starts_with?(trimmed_lower, "adicionar") ->
          item_text = extract_argument(trimmed_raw, "adicionar")
          handle_add(item_text, sender)

        String.starts_with?(trimmed_lower, "adiciona") ->
          item_text = extract_argument(trimmed_raw, "adiciona")
          handle_add(item_text, sender)

        String.starts_with?(trimmed_lower, "add") ->
          item_text = extract_argument(trimmed_raw, "add")
          handle_add(item_text, sender)

        String.starts_with?(trimmed_lower, "remover") ->
          item_text = extract_argument(trimmed_raw, "remover")
          handle_remove(item_text)

        String.starts_with?(trimmed_lower, "remove") ->
          item_text = extract_argument(trimmed_raw, "remove")
          handle_remove(item_text)

        true ->
          :ignore
      end
    end
  end

  def handle(_text, _sender), do: :ignore

  defp extract_argument(raw_text, command_prefix) do
    offset = String.length(command_prefix)
    String.slice(raw_text, offset..-1//1) |> String.trim()
  end

  defp handle_add("", _sender) do
    {:reply, "[BOT] Por favor especifica o item a adicionar, ex: 'adiciona leite'."}
  end

  defp handle_add(item_name, sender) do
    changeset = ShoppingItem.changeset(%ShoppingItem{}, %{name: item_name, added_by: sender})

    case Repo.insert(changeset) do
      {:ok, item} ->
        {:reply, "[BOT] ✅ Adicionado: #{item.name}"}

      {:error, _changeset} ->
        {:reply, "[BOT] Não foi possível adicionar o item à lista de compras."}
    end
  end

  defp handle_remove("") do
    {:reply, "[BOT] Por favor especifica o item a remover, ex: 'remove leite'."}
  end

  defp handle_remove(search_term) do
    query =
      from i in ShoppingItem,
        where: i.done == false and ilike(i.name, ^"%#{search_term}%"),
        order_by: [desc: i.inserted_at],
        limit: 1

    case Repo.one(query) do
      nil ->
        {:reply, "[BOT] O item '#{search_term}' não foi encontrado na lista de compras."}

      item ->
        Repo.delete!(item)
        {:reply, "[BOT] 🗑️ Removido: #{item.name}"}
    end
  end

  defp handle_list do
    query =
      from i in ShoppingItem,
        where: i.done == false,
        order_by: [asc: i.inserted_at]

    items = Repo.all(query)

    if items == [] do
      {:reply, "[BOT] 🛒 A tua lista de compras está vazia."}
    else
      formatted =
        items
        |> Enum.with_index(1)
        |> Enum.map(fn {item, idx} -> "#{idx}. #{item.name}" end)
        |> Enum.join("\n")

      {:reply, "[BOT] 🛒 Lista de Compras:\n" <> formatted}
    end
  end

  defp handle_clear do
    from(i in ShoppingItem, where: i.done == false)
    |> Repo.delete_all()

    {:reply, "[BOT] 🧹 Lista de compras limpa."}
  end
end
