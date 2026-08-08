defmodule Brain.LLM.Providers.Gemini do
  @moduledoc "Gemini-specific request/response handling."
  @behaviour Brain.LLM.Provider

  require Logger

  @endpoint "https://generativelanguage.googleapis.com/v1beta/models"
  @max_retries 2

  @impl true
  def generate_structured(system_prompt, user_prompt, schema) do
    request(system_prompt, user_prompt, schema, 15_000, retry?: true)
  end

  @impl true
  def generate_menu(system_prompt, user_prompt, schema) do
    request(system_prompt, user_prompt, schema, 120_000, retry?: false)
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

      post_with_retry(url, json: body, headers: headers, receive_timeout: 30_000)
    end
  end

  defp request(system_prompt, user_prompt, schema, receive_timeout, opts) do
    with {:ok, api_key} <- api_key() do
      url = "#{@endpoint}/#{model()}:generateContent"
      headers = [{"X-goog-api-key", api_key}, {"Content-Type", "application/json"}]

      req_opts = [
        json: build_body(system_prompt, user_prompt, schema),
        headers: headers,
        receive_timeout: receive_timeout
      ]

      if opts[:retry?] do
        post_with_retry(url, req_opts)
      else
        post_once(url, req_opts)
      end
    end
  end

  defp build_body(system_prompt, user_prompt, schema) do
    %{
      systemInstruction: %{parts: [%{text: system_prompt}]},
      contents: [%{role: "user", parts: [%{text: user_prompt}]}],
      generationConfig: %{
        temperature: 0,
        responseMimeType: "application/json",
        responseSchema: schema
      }
    }
  end

  defp post_with_retry(url, opts, retries \\ @max_retries) do
    case post_once(url, opts) do
      {:error, {:gemini_http_error, status, _body}} = error ->
        if retries > 0 and retryable_status?(status) do
          backoff_and_retry(url, opts, retries)
        else
          error
        end

      {:error, _exception} when retries > 0 ->
        backoff_and_retry(url, opts, retries)

      result ->
        result
    end
  end

  defp retryable_status?(429), do: true
  defp retryable_status?(status) when is_integer(status) and status >= 500, do: true
  defp retryable_status?(_), do: false

  defp backoff_and_retry(url, opts, retries) do
    delay = if retries >= @max_retries, do: 500, else: 1000

    Logger.warning(
      "[Brain] Gemini request failed, retrying in #{delay}ms (#{retries - 1} retries left)"
    )

    Process.sleep(delay)
    post_with_retry(url, opts, retries - 1)
  end

  defp post_once(url, opts) do
    case Req.post(url, opts) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        resp_body |> extract_text() |> decode_json()

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:gemini_http_error, status, resp_body}}

      {:error, exception} ->
        {:error, exception}
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
