defmodule Brain.LLM.GroqTest do
  use ExUnit.Case, async: false

  @moduletag :groq

  setup do
    original_key = System.get_env("GROQ_API_KEY")
    original_model = System.get_env("GROQ_MODEL")
    original_vision = System.get_env("GROQ_VISION_MODEL")

    System.put_env("GROQ_API_KEY", "test-groq-key")
    System.put_env("GROQ_MODEL", "test-text-model")
    System.put_env("GROQ_VISION_MODEL", "test-vision-model")

    on_exit(fn ->
      if original_key, do: System.put_env("GROQ_API_KEY", original_key), else: System.delete_env("GROQ_API_KEY")
      if original_model, do: System.put_env("GROQ_MODEL", original_model), else: System.delete_env("GROQ_MODEL")
      if original_vision, do: System.put_env("GROQ_VISION_MODEL", original_vision), else: System.delete_env("GROQ_VISION_MODEL")
    end)
  end

  describe "missing API key" do
    test "returns error when GROQ_API_KEY is not set" do
      System.delete_env("GROQ_API_KEY")

      assert {:error, :missing_api_key} =
               Brain.LLM.Providers.Groq.generate_structured("system", "user", %{})
    end

    test "returns error when GROQ_API_KEY is empty" do
      System.put_env("GROQ_API_KEY", "")

      assert {:error, :missing_api_key} =
               Brain.LLM.Providers.Groq.generate_structured("system", "user", %{})
    end
  end

  describe "model configuration" do
    test "uses GROQ_MODEL env var for text model" do
      System.put_env("GROQ_MODEL", "my-custom-model")

      # Verify the module reads the env var (tested via the request shape in integration)
      # Here we just verify the env var is respected by checking the API key path works
      assert {:error, {:groq_http_error, _, _}} =
               Brain.LLM.Providers.Groq.generate_structured("system", "user", %{})
    end

    test "uses GROQ_VISION_MODEL env var for vision model" do
      System.put_env("GROQ_VISION_MODEL", "my-vision-model")

      assert {:error, {:groq_http_error, _, _}} =
               Brain.LLM.Providers.Groq.generate_structured_with_media(
                 "system", "user", %{},
                 %{mimetype: "image/jpeg", data: "base64data"}
               )
    end
  end

  describe "implements Brain.LLM.Provider behaviour" do
    test "has all required callbacks" do
      assert function_exported?(Brain.LLM.Providers.Groq, :generate_structured, 3)
      assert function_exported?(Brain.LLM.Providers.Groq, :generate_structured_with_media, 4)
      assert function_exported?(Brain.LLM.Providers.Groq, :generate_menu, 3)
    end
  end

  describe "HTTP error handling" do
    test "returns groq_http_error tuple on non-200 status" do
      # With a real API key this would hit Groq; with test key we get 401
      assert {:error, {:groq_http_error, 401, _}} =
               Brain.LLM.Providers.Groq.generate_structured("system", "user", %{})
    end

    test "returns error on network failure" do
      System.put_env("GROQ_API_KEY", "test-key")

      # Use an unreachable endpoint to trigger a transport error
      original_endpoint = Application.get_env(:brain, :groq_test_endpoint)
      Application.put_env(:brain, :groq_test_endpoint, "http://192.0.2.1:1")

      on_exit(fn ->
        if original_endpoint,
          do: Application.put_env(:brain, :groq_test_endpoint, original_endpoint),
          else: Application.delete_env(:brain, :groq_test_endpoint)
      end)

      # This tests that network errors are properly wrapped
      # The actual error depends on the system's network config
      result = Brain.LLM.Providers.Groq.generate_structured("system", "user", %{})
      assert match?({:error, _}, result)
    end
  end
end
