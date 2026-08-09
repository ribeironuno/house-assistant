defmodule Brain.ShoppingList.InvoiceProcessor do
  @moduledoc """
  Processes receipt / invoice images sent via WhatsApp.

  Uses LLM Vision (Gemini) to extract purchased product names from receipt images,
  matches them against active items in the shopping list, removes matched items,
  adds the purchased items to the pantry, and formats a response message in Portuguese.
  """

  require Logger
  alias Brain.Pantry
  alias Brain.Repo
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
  def process_media(media, group_id \\ nil, sender \\ nil)

  def process_media(nil, _group_id, _sender), do: :ignore

  def process_media(media, group_id, sender) when is_map(media) do
    if enabled?() do
      case call_vision_provider(media) do
        {:ok, %{"purchased_items" => items}} when is_list(items) ->
          clean_items =
            items
            |> Enum.map(&to_string/1)
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          if clean_items == [] do
            {:reply,
             "[BOT] 🧾 Li a imagem, mas não consegui identificar nenhum produto da fatura."}
          else
            match_and_remove(clean_items, group_id, sender)
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

    if Code.ensure_loaded?(provider()) and
         function_exported?(provider(), :generate_structured_with_media, 4) do
      provider().generate_structured_with_media(@system_prompt, user_prompt, @schema, media)
    else
      {:error, :media_not_supported_by_provider}
    end
  end

  @doc """
  Matches extracted receipt items against the current shopping list items in Postgres,
  deletes matching items, adds the purchased items to the pantry, and formats the
  WhatsApp reply.  The pantry insert and shopping-list delete are wrapped in a
  single DB transaction so the two writes are always consistent.
  """
  def match_and_remove(purchased_items, group_id \\ nil, sender \\ nil) do
    active_items = ShoppingList.get_active_items(group_id)
    {removed_db_items, unmatched_receipt_items} = find_matches(active_items, purchased_items)

    Repo.transaction(fn ->
      pantry_added = add_to_pantry(purchased_items, group_id, sender)

      if removed_db_items != [] do
        ShoppingList.delete_items(removed_db_items)
      end

      build_reply(
        active_items,
        purchased_items,
        removed_db_items,
        unmatched_receipt_items,
        pantry_added
      )
    end)
    |> case do
      {:ok, reply} -> reply
      {:error, _} -> {:reply, "[BOT] 🧾 Ocorreu um erro ao processar a fatura."}
    end
  end

  defp build_reply(
         active_items,
         purchased_items,
         removed_db_items,
         unmatched_receipt_items,
         pantry_added
       ) do
    pantry_section = format_pantry_added(pantry_added)

    if active_items == [] do
      formatted_extracted = Enum.map_join(purchased_items, "\n", &"• #{&1}")

      {:reply,
       "[BOT] 🧾 Fatura lida com sucesso!\n\n🛒 A tua lista de compras estava vazia, por isso nenhum item foi removido.\n\nProdutos na fatura:\n#{formatted_extracted}#{pantry_section}"}
    else
      if removed_db_items == [] do
        formatted_receipt = Enum.take(purchased_items, 5) |> Enum.join(", ")

        {:reply,
         "[BOT] 🧾 Fatura lida (#{formatted_receipt}), mas nenhum dos produtos comprados estava na tua lista de compras.#{pantry_section}"}
      else
        removed_names = Enum.map(removed_db_items, & &1.name)
        formatted_removed = Enum.map_join(removed_names, "\n", &"• #{&1}")

        msg =
          "[BOT] 🧾 Fatura processada!\n\n🗑️ Removidos da lista de compras:\n#{formatted_removed}"

        final_msg =
          if unmatched_receipt_items == [] do
            msg
          else
            other_names = Enum.take(unmatched_receipt_items, 5)
            msg <> "\n\n(Outros itens na fatura: #{Enum.join(other_names, ", ")})"
          end

        {:reply, final_msg <> pantry_section}
      end
    end
  end

  @doc """
  Adds purchased items to the pantry, skipping items that are already there
  (compared case-insensitively). Returns the list of inserted pantry items.
  """
  def add_to_pantry(purchased_items, group_id, sender) do
    existing_names =
      Pantry.get_all(group_id)
      |> Enum.map(&normalize(&1.name))

    new_items =
      Enum.reject(purchased_items, fn item ->
        normalize(item) in existing_names
      end)

    case Pantry.add_many_models(new_items, group_id, sender) do
      {:ok, inserted} -> inserted
      {:error, _} -> []
    end
  end

  defp format_pantry_added([]), do: ""

  defp format_pantry_added(items) do
    names = Enum.map(items, & &1.name)
    "\n\n🏠 Adicionados à despensa:\n" <> Enum.map_join(names, "\n", &"• #{&1}")
  end

  @doc """
  Finds matching DB shopping list items given a list of purchased items from a receipt.
  Uses fast string matching first, then LLM semantic matching for remaining unmatched pairs.
  Each receipt item matches at most one DB item (1:1).
  Returns `{matched_db_items, unmatched_receipt_items}`.
  """
  def find_matches(active_items, purchased_items) do
    {string_matched, unmatched_db, unmatched_receipt} =
      string_match(active_items, purchased_items)

    if unmatched_db == [] or unmatched_receipt == [] do
      {string_matched, unmatched_receipt}
    else
      case llm_semantic_match(unmatched_db, unmatched_receipt) do
        {:ok, additional_db_matches, matched_receipt_names} ->
          # Enforce 1:1: LLM matches must not overlap with string matches
          already_matched =
            MapSet.new(string_matched, &normalize(&1.name))

          additional_filtered =
            Enum.reject(additional_db_matches, fn db_item ->
              MapSet.member?(already_matched, normalize(db_item.name))
            end)

          final_matched = string_matched ++ additional_filtered

          final_unmatched =
            Enum.reject(unmatched_receipt, fn receipt_item ->
              Enum.any?(matched_receipt_names, &(normalize(&1) == normalize(receipt_item)))
            end)

          {final_matched, final_unmatched}

        :error ->
          {string_matched, unmatched_receipt}
      end
    end
  end

  @min_match_length 4

  defp string_match(active_items, purchased_items) do
    # Greedy 1:1 matching: each receipt item claims at most one DB item.
    {matched_db_items, unmatched_receipt} =
      Enum.reduce(purchased_items, {[], []}, fn receipt_item, {matched_db, unmatched} ->
        receipt_norm = normalize(receipt_item)

        case Enum.find(active_items, fn db_item ->
               db_item not in matched_db and
                 items_match?(normalize(db_item.name), receipt_norm)
             end) do
          nil ->
            {matched_db, [receipt_item | unmatched]}

          db_item ->
            {[db_item | matched_db], unmatched}
        end
      end)

    matched_db_items = Enum.reverse(matched_db_items)
    unmatched_db = active_items -- matched_db_items
    unmatched_receipt = Enum.reverse(unmatched_receipt)

    {matched_db_items, unmatched_db, unmatched_receipt}
  end

  @doc """
  Uses LLM to semantically match unmatched items (e.g., "piripiri" <-> "tabasco chipotle").
  Returns `{:ok, matched_db_items, matched_receipt_names}` or `:error`.
  """
  def llm_semantic_match(unmatched_db_items, unmatched_receipt_items) do
    db_names = Enum.map(unmatched_db_items, & &1.name)

    prompt = """
    Dada uma lista de compras e itens de uma fatura, identifique quais itens da lista de compras correspondem semanticamente aos itens da fatura, mesmo que os nomes sejam diferentes.

    Lista de compras: #{inspect(db_names)}
    Itens da fatura: #{inspect(unmatched_receipt_items)}

    Retorne apenas os nomes exatos da lista de compras que têm correspondência semântica com algum item da fatura, e qual item da fatura corresponde.
    Exemplos de correspondências semânticas: "piripiri" <-> "tabasco", "molho picante" <-> "sriracha", "azeite" <-> "azeite virgem extra".

    Retorne um JSON com os pares de correspondência. Se não houver correspondências, retorne listas vazias.
    """

    schema = %{
      type: "object",
      properties: %{
        matches: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              list_item: %{type: "string", description: "Nome exato da lista de compras"},
              receipt_item: %{type: "string", description: "Nome exato do item da fatura"}
            },
            required: ["list_item", "receipt_item"]
          }
        }
      },
      required: ["matches"]
    }

    if Code.ensure_loaded?(provider()) and
         function_exported?(provider(), :generate_structured, 3) do
      case provider().generate_structured(
             "Você é um assistente que identifica correspondências semânticas entre itens de supermercado em português.",
             prompt,
             schema
           ) do
        {:ok, %{"matches" => matches}} when is_list(matches) ->
          validated_matches =
            Enum.filter(matches, fn match ->
              valid_match_pair?(match, unmatched_db_items, unmatched_receipt_items)
            end)

          matched_db_items =
            Enum.filter(unmatched_db_items, fn db_item ->
              Enum.any?(validated_matches, fn m ->
                normalize(m["list_item"]) == normalize(db_item.name)
              end)
            end)

          matched_receipt_names = Enum.map(validated_matches, & &1["receipt_item"])

          {:ok, matched_db_items, matched_receipt_names}

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp valid_match_pair?(match, unmatched_db_items, unmatched_receipt_items) do
    is_map(match) and
      is_binary(match["list_item"]) and
      is_binary(match["receipt_item"]) and
      Enum.any?(unmatched_db_items, fn db_item ->
        normalize(match["list_item"]) == normalize(db_item.name)
      end) and
      Enum.any?(unmatched_receipt_items, fn receipt_item ->
        normalize(match["receipt_item"]) == normalize(receipt_item)
      end)
  end

  @doc """
  Determines if an item on the shopping list matches an item on the receipt.
  Checks exact equality, substring match, and word overlap.
  Conservative by design: ambiguous matches are deferred to LLM semantic matching
  instead of auto-deleting unrelated items (e.g. "sal" vs "salada",
  "leite" vs "leite de coco").
  """
  def items_match?(item_norm, receipt_norm)
      when is_binary(item_norm) and is_binary(receipt_norm) do
    cond do
      item_norm == receipt_norm ->
        true

      substring_match?(item_norm, receipt_norm) ->
        true

      word_overlap?(item_norm, receipt_norm) ->
        true

      true ->
        false
    end
  end

  def items_match?(_, _), do: false

  @doc false
  defp substring_match?(a, b) do
    shorter = if String.length(a) <= String.length(b), do: a, else: b
    longer = if shorter == a, do: b, else: a

    String.length(shorter) >= @min_match_length and
      String.contains?(longer, shorter) and
      String.length(shorter) / max(String.length(longer), 1) >= 0.5
  end

  defp word_overlap?(a, b) do
    words_a = significant_words(a)
    words_b = significant_words(b)

    if words_a == [] or words_b == [] do
      false
    else
      Enum.any?(words_a, fn w ->
        String.length(w) >= @min_match_length and
          w in words_b and
          String.length(w) / max(String.length(a), String.length(b)) >= 0.5
      end)
    end
  end

  @stop_words ~w(de do da dos das e em para com sem por ou)
  defp significant_words(str) do
    String.split(str)
    |> Enum.reject(&(&1 in @stop_words))
  end

  defp normalize(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.trim()
  end
end
