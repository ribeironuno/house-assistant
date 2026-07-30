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
end
