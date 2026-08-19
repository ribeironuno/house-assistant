defmodule Brain.LLM.Providers.Groq do
  @moduledoc "Groq-specific request/response handling (OpenAI-compatible API)."
  @behaviour Brain.LLM.Provider

  require Logger

  @endpoint "https://api.groq.com/openai/v1/chat/completions"
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
      model = vision_model()
      schema_instruction = schema_instruction(schema)

      enriched_system =
        if schema_instruction != "",
          do: system_prompt <> "\n\n" <> schema_instruction,
          else: system_prompt

      body = %{
        model: model,
        messages: [
          %{role: "system", content: enriched_system},
          %{
            role: "user",
            content: [
              %{type: "text", text: user_prompt},
              %{
                type: "image_url",
                image_url: %{url: "data:#{mimetype};base64,#{base64_data}"}
              }
            ]
          }
        ],
        temperature: 0
      }

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      post_with_retry(json: body, headers: headers, receive_timeout: 30_000)
    end
  end

  defp request(system_prompt, user_prompt, schema, receive_timeout, opts) do
    with {:ok, api_key} <- api_key() do
      model = text_model()
      schema_instruction = schema_instruction(schema)

      enriched_system =
        if schema_instruction != "",
          do: system_prompt <> "\n\n" <> schema_instruction,
          else: system_prompt

      body = %{
        model: model,
        messages: [
          %{role: "system", content: enriched_system},
          %{role: "user", content: user_prompt}
        ],
        temperature: 0
      }

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      req_opts = [
        json: body,
        headers: headers,
        receive_timeout: receive_timeout
      ]

      if opts[:retry?] do
        post_with_retry(req_opts)
      else
        post_once(req_opts)
      end
    end
  end

  defp schema_instruction(schema) do
    case Jason.encode(schema) do
      {:ok, encoded} ->
        "Respond ONLY with valid JSON matching this schema: #{encoded}"

      {:error, _} ->
        ""
    end
  end

  defp post_with_retry(opts, retries \\ @max_retries) do
    case post_once(opts) do
      {:error, {:groq_http_error, status, _body}} = error ->
        if retries > 0 and retryable_status?(status) do
          backoff_and_retry(opts, retries)
        else
          error
        end

      {:error, _exception} when retries > 0 ->
        backoff_and_retry(opts, retries)

      result ->
        result
    end
  end

  defp retryable_status?(429), do: true
  defp retryable_status?(status) when is_integer(status) and status >= 500, do: true
  defp retryable_status?(_), do: false

  defp backoff_and_retry(opts, retries) do
    delay = if retries >= @max_retries, do: 500, else: 1000

    Logger.warning(
      "[Brain] Groq request failed, retrying in #{delay}ms (#{retries - 1} retries left)"
    )

    Process.sleep(delay)
    post_with_retry(opts, retries - 1)
  end

  defp post_once(opts) do
    case Req.post(@endpoint, opts) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        resp_body |> extract_text() |> decode_json()

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:groq_http_error, status, resp_body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp api_key do
    case System.get_env("GROQ_API_KEY") do
      nil -> {:error, :missing_api_key}
      "" -> {:error, :missing_api_key}
      key -> {:ok, key}
    end
  end

  defp text_model, do: System.get_env("GROQ_MODEL", "llama-3.3-70b-versatile")

  defp vision_model,
    do: System.get_env("GROQ_VISION_MODEL", "llama-4-scout-17b-16e-instruct")

  defp extract_text(%{
         "choices" => [%{"message" => %{"content" => text}} | _]
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
