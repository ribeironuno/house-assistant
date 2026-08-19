defmodule Brain.LLM.Providers.Fallback do
  @moduledoc """
  Wraps a configurable chain of LLM providers. Tries the first provider;
  on a retryable failure, falls through to the next. If all fail, returns
  the last error.
  """
  @behaviour Brain.LLM.Provider

  require Logger

  @impl true
  def generate_structured(system_prompt, user_prompt, schema) do
    with_fallback(fn provider -> provider.generate_structured(system_prompt, user_prompt, schema) end)
  end

  @impl true
  def generate_structured_with_media(system_prompt, user_prompt, schema, media) do
    with_fallback(fn provider ->
      provider.generate_structured_with_media(system_prompt, user_prompt, schema, media)
    end)
  end

  @impl true
  def generate_menu(system_prompt, user_prompt, schema) do
    with_fallback(fn provider -> provider.generate_menu(system_prompt, user_prompt, schema) end)
  end

  defp with_fallback(fun) do
    providers = fallback_chain()

    Enum.reduce_while(providers, nil, fn provider, _prev_error ->
      Logger.info("[Brain] Trying LLM provider #{inspect(provider)}")

      case fun.(provider) do
        {:ok, _} = success ->
          {:halt, success}

        {:error, reason} = error ->
          if retryable?(reason) do
            Logger.warning(
              "[Brain] #{inspect(provider)} failed (#{inspect(reason)}), trying next provider"
            )

            {:cont, error}
          else
            Logger.error("[Brain] #{inspect(provider)} failed with non-retryable error: #{inspect(reason)}")
            {:halt, error}
          end
      end
    end)
    |> case do
      nil -> {:error, :all_providers_failed}
      result -> result
    end
  end

  defp fallback_chain do
    Application.get_env(:brain, :llm_fallback_chain, [
      Brain.LLM.Providers.Groq,
      Brain.LLM.Providers.Gemini
    ])
  end

  defp retryable?(:missing_api_key), do: true
  defp retryable?(:missing_llm_text), do: true
  defp retryable?(%Jason.DecodeError{}), do: true

  defp retryable?({:gemini_http_error, status, _})
       when is_integer(status) and (status == 429 or status >= 500),
       do: true

  defp retryable?({:groq_http_error, status, _})
       when is_integer(status) and (status == 429 or status >= 500),
       do: true

  defp retryable?(%Req.TransportError{}), do: true
  defp retryable?(_), do: false
end
