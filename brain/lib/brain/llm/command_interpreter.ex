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
          "help",
          "ignore"
        ]
      },
      confidence: %{type: "number"},
      items: %{type: "array", items: %{type: "string"}},
      item: %{type: "string"},
      reminder_text: %{type: "string"},
      reminder_time_phrase: %{type: "string"}
    },
    required: ["action", "confidence"]
  }

  def interpret(text) when is_binary(text) do
    if enabled?() do
      user_prompt =
        "Message: #{text}\nCurrent date/time UTC: #{DateTime.utc_now() |> DateTime.to_iso8601()}"

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

  defp to_canonical_command(%{"confidence" => c}) when c < @min_confidence, do: :ignore

  defp to_canonical_command(%{"action" => "add_items", "items" => items}) when is_list(items) do
    items
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> :ignore
      clean -> {:ok, "adiciona " <> Enum.join(clean, ", ")}
    end
  end

  defp to_canonical_command(%{"action" => "remove_item", "item" => item}) when is_binary(item) do
    case String.trim(item) do
      "" -> :ignore
      trimmed -> {:ok, "remove " <> trimmed}
    end
  end

  defp to_canonical_command(%{"action" => "list_items"}), do: {:ok, "lista"}
  defp to_canonical_command(%{"action" => "clear_items"}), do: {:ok, "limpar lista"}
  defp to_canonical_command(%{"action" => "help"}), do: {:ok, "ajuda"}

  defp to_canonical_command(%{
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

  defp to_canonical_command(%{"action" => "ignore"}), do: :ignore
  defp to_canonical_command(_), do: :ignore

  defp log_and_ignore(reason) do
    Logger.warning("[Brain] LLM command interpreter ignored message: #{inspect(reason)}")
    :ignore
  end
end
