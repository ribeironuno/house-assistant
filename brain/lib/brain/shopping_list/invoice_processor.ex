defmodule Brain.ShoppingList.InvoiceProcessor do
  @moduledoc """
  Processes receipt / invoice images sent via WhatsApp.

  Uses LLM Vision (Gemini) to extract purchased product names from receipt images,
  matches them against active items in the shopping list, removes matched items,
  and formats a response message in Portuguese.
  """

  require Logger
  alias Brain.ShoppingList

  @schema %{
    type: "object",
    properties: %{
      purchased_items: %{
        type: "array",
        items: %{type: "string"},
        description:
          "List of clean, everyday Portuguese item names extracted from the receipt (e.g. 'leite', 'ovos', 'banana', 'detergente loiça'). Omit prices, totals, discounts, taxes, store names."
      }
    },
    required: ["purchased_items"]
  }

  @system_prompt """
  Você é um assistente especializado em ler faturas e talões de compras de supermercado (Continente, Pingo Doce, Auchan, Mercadona, etc.).
  Analise a imagem da fatura/recibo e extraia a lista dos produtos comprados.
  Regras:
  1. Extraia apenas nomes legíveis dos produtos alimentares ou de mercearia/casa comprados.
  2. Simplifique e normalize abreviações típicas de talões para nomes comuns em português do dia-a-dia (por exemplo: "LEITE M GORDO MIMOSA" -> "leite", "BANANA CACHO" -> "banana", "PAO DE FORMA S/CRUSTA" -> "pão de forma").
  3. Ignore totalmente totais, subtotais, IVAs, nifs, descontos, formas de pagamento, linhas de troco, endereços e nomes de lojas.
  4. Retorne a lista de produtos no campo JSON `purchased_items`.
  """

  @doc """
  Processes an incoming image media object and returns `{:reply, text}` or `:ignore`.
  """
  def process_media(media, sender \\ nil)

  def process_media(nil, _sender), do: :ignore

  def process_media(media, _sender) when is_map(media) do
    if enabled?() do
      case call_vision_provider(media) do
        {:ok, %{"purchased_items" => items}} when is_list(items) ->
          clean_items =
            items
            |> Enum.map(&to_string/1)
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          if clean_items == [] do
            {:reply, "[BOT] 🧾 Li a imagem, mas não consegui identificar nenhum produto da fatura."}
          else
            match_and_remove(clean_items)
          end

        {:error, reason} ->
          Logger.warning("[Brain] Invoice processor failed: #{inspect(reason)}")
          {:reply, "[BOT] 🧾 Não foi possível ler a fatura (erro no processamento da imagem)."}

        _ ->
          {:reply, "[BOT] 🧾 Não consegui extrair os produtos dessa fatura."}
      end
    else
      :ignore
    end
  rescue
    exception ->
      Logger.error("[Brain] Invoice processor exception: #{Exception.message(exception)}")
      {:reply, "[BOT] 🧾 Ocorreu um erro ao processar a fatura."}
  end

  defp enabled?, do: Application.get_env(:brain, :llm_command_interpreter_enabled, true)

  defp provider, do: Application.get_env(:brain, :llm_provider, Brain.LLM.Providers.Gemini)

  defp call_vision_provider(media) do
    user_prompt = "Por favor analisa esta fatura/recibo e extrai a lista de produtos comprados."

    if function_exported?(provider(), :generate_structured_with_media, 4) do
      provider().generate_structured_with_media(@system_prompt, user_prompt, @schema, media)
    else
      {:error, :media_not_supported_by_provider}
    end
  end

  @doc """
  Matches extracted receipt items against the current shopping list items in Postgres,
  deletes matching items, and formats the WhatsApp reply.
  """
  def match_and_remove(purchased_items) do
    active_items = ShoppingList.get_active_items()

    if active_items == [] do
      formatted_extracted = Enum.map_join(purchased_items, "\n", &"• #{&1}")
      {:reply, "[BOT] 🧾 Fatura lida com sucesso!\n\n🛒 A tua lista de compras estava vazia, por isso nenhum item foi removido.\n\nProdutos na fatura:\n#{formatted_extracted}"}
    else
      {removed_db_items, unmatched_receipt_items} = find_matches(active_items, purchased_items)

      if removed_db_items == [] do
        formatted_receipt = Enum.take(purchased_items, 5) |> Enum.join(", ")
        {:reply, "[BOT] 🧾 Fatura lida (#{formatted_receipt}), mas nenhum dos produtos comprados estava na tua lista de compras."}
      else
        ShoppingList.delete_items(removed_db_items)

        removed_names = Enum.map(removed_db_items, & &1.name)
        formatted_removed = Enum.map_join(removed_names, "\n", &"• #{&1}")

        msg = "[BOT] 🧾 Fatura processada!\n\n🗑️ Removidos da lista de compras:\n#{formatted_removed}"

        final_msg =
          if unmatched_receipt_items == [] do
            msg
          else
            other_names = Enum.take(unmatched_receipt_items, 5)
            msg <> "\n\n(Outros itens na fatura: #{Enum.join(other_names, ", ")})"
          end

        {:reply, final_msg}
      end
    end
  end

  @doc """
  Finds matching DB shopping list items given a list of purchased items from a receipt.
  Returns `{matched_db_items, unmatched_receipt_items}`.
  """
  def find_matches(active_items, purchased_items) do
    purchased_normalized = Enum.map(purchased_items, &normalize/1)

    {matched_db_items, _unmatched_db_items} =
      Enum.split_with(active_items, fn db_item ->
        item_norm = normalize(db_item.name)

        Enum.any?(purchased_normalized, fn receipt_item_norm ->
          items_match?(item_norm, receipt_item_norm)
        end)
      end)

    unmatched_receipt =
      Enum.reject(purchased_items, fn receipt_item ->
        receipt_norm = normalize(receipt_item)

        Enum.any?(matched_db_items, fn db_item ->
          items_match?(normalize(db_item.name), receipt_norm)
        end)
      end)

    {matched_db_items, unmatched_receipt}
  end

  @doc """
  Determines if an item on the shopping list matches an item on the receipt.
  Checks exact equality, substring match, and word overlap.
  """
  def items_match?(item_norm, receipt_norm) when is_binary(item_norm) and is_binary(receipt_norm) do
    cond do
      item_norm == receipt_norm ->
        true

      String.contains?(receipt_norm, item_norm) or String.contains?(item_norm, receipt_norm) ->
        true

      word_overlap?(item_norm, receipt_norm) ->
        true

      true ->
        false
    end
  end

  def items_match?(_, _), do: false

  defp word_overlap?(a, b) do
    words_a = String.split(a) |> Enum.reject(&(&1 in ["de", "do", "da", "dos", "das", "e", "em", "para", "com"]))
    words_b = String.split(b) |> Enum.reject(&(&1 in ["de", "do", "da", "dos", "das", "e", "em", "para", "com"]))

    if words_a == [] or words_b == [] do
      false
    else
      Enum.any?(words_a, fn w -> w in words_b end)
    end
  end

  defp normalize(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.trim()
  end
end
