defmodule Brain.LLM.Provider do
  @moduledoc """
  Contract for any LLM provider used to interpret free-form text into a
  structured response. Providers only handle their own API's request/response
  shape — prompt content and command mapping live in `CommandInterpreter`.
  """

  @callback generate_structured(
              system_prompt :: String.t(),
              user_prompt :: String.t(),
              schema :: map()
            ) ::
              {:ok, map()} | {:error, term()}

  @callback generate_structured_with_media(
              system_prompt :: String.t(),
              user_prompt :: String.t(),
              schema :: map(),
              media :: %{mimetype: String.t(), data: String.t()}
            ) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Generates a structured response for heavy tasks (e.g. a full weekly menu
  with recipes). Providers should use a significantly longer timeout here.
  """
  @callback generate_menu(
              system_prompt :: String.t(),
              user_prompt :: String.t(),
              schema :: map()
            ) ::
              {:ok, map()} | {:error, term()}
end
