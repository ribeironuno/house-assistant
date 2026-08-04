defmodule Brain.LLM.Providers.TestStub do
  @moduledoc """
  Deterministic LLM provider stub for tests. Defaults to `{:error, :test_stub}`
  so tests never hit the network or spend tokens. Use `set_response/1` to
  simulate a specific LLM answer for the happy paths.
  """
  @behaviour Brain.LLM.Provider

  @key {__MODULE__, :response}

  @doc "Sets the response returned by all provider callbacks."
  def set_response(response), do: :persistent_term.put(@key, response)

  @doc "Resets to the default error response."
  def reset, do: :persistent_term.erase(@key)

  defp response do
    case :persistent_term.get(@key, :default) do
      :default -> {:error, :test_stub}
      {:ok, _} = ok -> ok
    end
  end

  @impl true
  def generate_structured(_system_prompt, _user_prompt, _schema), do: response()

  @impl true
  def generate_menu(_system_prompt, _user_prompt, _schema), do: response()

  @impl true
  def generate_structured_with_media(_system_prompt, _user_prompt, _schema, _media),
    do: response()
end
