defmodule Brain.LLM.Providers.TestStub do
  @moduledoc """
  Deterministic LLM provider stub for tests. Always returns `{:error, :test_stub}`
  so tests never hit the network or spend tokens.
  """
  @behaviour Brain.LLM.Provider

  @impl true
  def generate_structured(_system_prompt, _user_prompt, _schema), do: {:error, :test_stub}

  @impl true
  def generate_menu(_system_prompt, _user_prompt, _schema), do: {:error, :test_stub}

  @impl true
  def generate_structured_with_media(_system_prompt, _user_prompt, _schema, _media),
    do: {:error, :test_stub}
end
