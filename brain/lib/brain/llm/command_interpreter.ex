defmodule Brain.LLM.CommandInterpreter do
  @moduledoc """
  Provider-agnostic: builds the prompt/schema, calls the configured provider,
  and maps the structured result to a canonical command string that
  `Brain.Commands` already knows how to route.
  """

  require Logger
  alias Brain.LLM.PromptHelper

  @min_confidence 0.65

  @schema %{
    type: "object",
    properties: %{
      action: %{
        type: "string",
        enum: [
          "add_items",
          "remove_item",
          "list_items",
          "clear_items",
          "set_reminder",
          "add_pantry_items",
          "remove_pantry_item",
          "list_pantry",
          "clear_pantry",
          "generate_menu",
          "get_recipe",
          "rate_meal",
          "help",
          "ignore"
        ]
      },
      confidence: %{type: "number"},
      items: %{type: "array", items: %{type: "string"}},
      item: %{type: "string"},
      reminder_text: %{type: "string"},
      reminder_time_phrase: %{type: "string"},
      constraints: %{type: "string"},
      sentiment: %{type: "string"}
    },
    required: ["action", "confidence"]
  }

  def interpret(text) when is_binary(text) do
    if enabled?() do
      capped_text = String.slice(text, 0, 500)

      user_prompt =
        "Message: #{capped_text}\nCurrent date/time UTC: #{DateTime.utc_now() |> DateTime.to_iso8601()}"

      case provider().generate_structured(PromptHelper.build(), user_prompt, @schema) do
        {:ok, interpretation} -> to_canonical_command(interpretation)
        {:error, reason} -> log_and_ignore(reason)
      end
    else
      :ignore
    end
  rescue
    exception ->
      Logger.error("[Brain] LLM command interpreter failed: #{Exception.message(exception)}")
      :ignore
  end

  def interpret(_text), do: :ignore

  defp enabled?, do: Application.get_env(:brain, :llm_command_interpreter_enabled, true)

  defp provider, do: Application.get_env(:brain, :llm_provider, Brain.LLM.Providers.Gemini)

  # Confidence gate: requires a numeric confidence >= @min_confidence.
  # Missing / non-numeric / below-threshold confidence is ignored so the
  # gate cannot be bypassed by omitting the field.
  defp to_canonical_command(%{"confidence" => c} = map)
       when is_number(c) and c >= @min_confidence,
       do: do_canonical(map)

  defp to_canonical_command(_), do: :ignore

  defp do_canonical(%{"action" => "add_items", "items" => items}) when is_list(items) do
    items
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> :ignore
      clean -> {:ok, "adiciona " <> Enum.join(clean, ", ")}
    end
  end

  defp do_canonical(%{"action" => "remove_item", "item" => item}) when is_binary(item) do
    case String.trim(item) do
      "" -> :ignore
      trimmed -> {:ok, "remove " <> trimmed}
    end
  end

  defp do_canonical(%{"action" => "list_items"}), do: {:ok, "lista"}
  defp do_canonical(%{"action" => "clear_items"}), do: {:ok, "limpar lista"}
  defp do_canonical(%{"action" => "help"}), do: {:ok, "ajuda"}

  defp do_canonical(%{
         "action" => "set_reminder",
         "reminder_text" => text,
         "reminder_time_phrase" => phrase
       })
       when is_binary(text) and is_binary(phrase) do
    case {String.trim(text), String.trim(phrase)} do
      {"", _} -> :ignore
      {_, ""} -> :ignore
      {t, p} -> {:ok, "lembrar de #{t} #{p}"}
    end
  end

  defp do_canonical(%{"action" => "ignore"}), do: :ignore

  defp do_canonical(%{"action" => "add_pantry_items", "items" => items})
       when is_list(items) do
    clean_items =
      items
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case clean_items do
      [] -> :ignore
      items_list -> {:ok, {:add_pantry_items, items_list}}
    end
  end

  defp do_canonical(%{"action" => "remove_pantry_item", "item" => item})
       when is_binary(item) do
    case String.trim(item) do
      "" -> :ignore
      trimmed -> {:ok, {:remove_pantry_item, trimmed}}
    end
  end

  defp do_canonical(%{"action" => "list_pantry"}), do: {:ok, :list_pantry}
  defp do_canonical(%{"action" => "clear_pantry"}), do: {:ok, :clear_pantry}

  defp do_canonical(%{"action" => "generate_menu", "constraints" => constraints})
       when is_binary(constraints) do
    {:ok, {:generate_menu, String.trim(constraints)}}
  end

  defp do_canonical(%{"action" => "generate_menu"}) do
    {:ok, {:generate_menu, ""}}
  end

  defp do_canonical(%{"action" => "get_recipe", "item" => item}) when is_binary(item) do
    case String.trim(item) do
      "" -> :ignore
      trimmed -> {:ok, {:get_recipe, trimmed}}
    end
  end

  defp do_canonical(%{"action" => "rate_meal", "item" => item, "sentiment" => sentiment})
       when is_binary(item) and is_binary(sentiment) do
    case {String.trim(item), String.trim(sentiment)} do
      {"", _} -> :ignore
      {_, ""} -> :ignore
      {meal, s} when s in ["like", "dislike"] -> {:ok, {:rate_meal, meal, s}}
      _ -> :ignore
    end
  end

  defp do_canonical(_), do: :ignore

  defp log_and_ignore(reason) do
    Logger.warning("[Brain] LLM command interpreter ignored message: #{inspect(reason)}")
    :ignore
  end
end
