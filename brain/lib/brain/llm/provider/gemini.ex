defmodule Brain.LLM.Providers.Gemini do
  @moduledoc "Gemini-specific request/response handling."
  @behaviour Brain.LLM.Provider

  @endpoint "https://generativelanguage.googleapis.com/v1beta/models"

  @impl true
  def generate_structured(system_prompt, user_prompt, schema) do
    with {:ok, api_key} <- api_key() do
      url = "#{@endpoint}/#{model()}:generateContent"

      body = %{
        systemInstruction: %{parts: [%{text: system_prompt}]},
        contents: [%{role: "user", parts: [%{text: user_prompt}]}],
        generationConfig: %{
          temperature: 0,
          responseMimeType: "application/json",
          responseSchema: schema
        }
      }

      headers = [{"X-goog-api-key", api_key}, {"Content-Type", "application/json"}]

      case Req.post(url, json: body, headers: headers, receive_timeout: 8_000) do
        {:ok, %Req.Response{status: 200, body: resp_body}} ->
          resp_body |> extract_text() |> decode_json()

        {:ok, %Req.Response{status: status, body: resp_body}} ->
          {:error, {:gemini_http_error, status, resp_body}}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  @impl true
  def generate_structured_with_media(system_prompt, user_prompt, schema, media) do
    mimetype = Map.get(media, :mimetype) || Map.get(media, "mimetype")
    base64_data = Map.get(media, :data) || Map.get(media, "data")

    with {:ok, api_key} <- api_key() do
      url = "#{@endpoint}/#{model()}:generateContent"

      body = %{
        systemInstruction: %{parts: [%{text: system_prompt}]},
        contents: [
          %{
            role: "user",
            parts: [
              %{inlineData: %{mimeType: mimetype, data: base64_data}},
              %{text: user_prompt}
            ]
          }
        ],
        generationConfig: %{
          temperature: 0,
          responseMimeType: "application/json",
          responseSchema: schema
        }
      }

      headers = [{"X-goog-api-key", api_key}, {"Content-Type", "application/json"}]

      case Req.post(url, json: body, headers: headers, receive_timeout: 30_000) do
        {:ok, %Req.Response{status: 200, body: resp_body}} ->
          resp_body |> extract_text() |> decode_json()

        {:ok, %Req.Response{status: status, body: resp_body}} ->
          {:error, {:gemini_http_error, status, resp_body}}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  defp api_key do
    case System.get_env("GEMINI_API_KEY") do
      nil -> {:error, :missing_api_key}
      "" -> {:error, :missing_api_key}
      key -> {:ok, key}
    end
  end

  defp model, do: System.get_env("GEMINI_MODEL", "gemini-flash-latest")

  defp extract_text(%{
         "candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]
       })
       when is_binary(text),
       do: {:ok, text}

  defp extract_text(_body), do: {:error, :missing_llm_text}

  defp decode_json({:ok, text}) do
    case Jason.decode(text) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, error} -> {:error, error}
    end
  end

  defp decode_json(error), do: error
end
