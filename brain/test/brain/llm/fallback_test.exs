defmodule Brain.LLM.FallbackTest do
  use ExUnit.Case, async: false

  defmodule FakePrimary do
    @behaviour Brain.LLM.Provider

    def set_reply(reply), do: Process.put({__MODULE__, :reply}, reply)

    def generate_structured(_s, _u, _sch), do: Process.get({__MODULE__, :reply}) || {:error, :no_reply}
    def generate_menu(_s, _u, _sch), do: Process.get({__MODULE__, :reply}) || {:error, :no_reply}
    def generate_structured_with_media(_s, _u, _sch, _m), do: Process.get({__MODULE__, :reply}) || {:error, :no_reply}
  end

  defmodule FakeSecondary do
    @behaviour Brain.LLM.Provider

    def set_reply(reply), do: Process.put({__MODULE__, :reply}, reply)

    def generate_structured(_s, _u, _sch), do: Process.get({__MODULE__, :reply}) || {:error, :no_reply}
    def generate_menu(_s, _u, _sch), do: Process.get({__MODULE__, :reply}) || {:error, :no_reply}
    def generate_structured_with_media(_s, _u, _sch, _m), do: Process.get({__MODULE__, :reply}) || {:error, :no_reply}
  end

  setup do
    original_chain = Application.get_env(:brain, :llm_fallback_chain)
    original_provider = Application.get_env(:brain, :llm_provider)

    Application.put_env(:brain, :llm_fallback_chain, [FakePrimary, FakeSecondary])
    Application.put_env(:brain, :llm_provider, Brain.LLM.Providers.Fallback)

    FakePrimary.set_reply(nil)
    FakeSecondary.set_reply(nil)

    on_exit(fn ->
      if original_chain, do: Application.put_env(:brain, :llm_fallback_chain, original_chain), else: Application.delete_env(:brain, :llm_fallback_chain)
      Application.put_env(:brain, :llm_provider, original_provider)
    end)
  end

  describe "primary succeeds" do
    test "secondary is never called" do
      FakePrimary.set_reply({:ok, %{"action" => "list_items"}})

      assert {:ok, %{"action" => "list_items"}} =
               Brain.LLM.Providers.Fallback.generate_structured("sys", "user", %{})
    end
  end

  describe "primary times out -> secondary succeeds" do
    test "falls back to secondary on timeout" do
      FakePrimary.set_reply({:error, %Req.TransportError{reason: :timeout}})
      FakeSecondary.set_reply({:ok, %{"action" => "add_items"}})

      assert {:ok, %{"action" => "add_items"}} =
               Brain.LLM.Providers.Fallback.generate_structured("sys", "user", %{})
    end
  end

  describe "primary returns 5xx -> secondary succeeds" do
    test "falls back to secondary on server error" do
      FakePrimary.set_reply({:error, {:gemini_http_error, 503, %{}}})
      FakeSecondary.set_reply({:ok, %{"action" => "list_pantry"}})

      assert {:ok, %{"action" => "list_pantry"}} =
               Brain.LLM.Providers.Fallback.generate_structured("sys", "user", %{})
    end
  end

  describe "primary returns 429 -> secondary succeeds" do
    test "falls back to secondary on rate limit" do
      FakePrimary.set_reply({:error, {:gemini_http_error, 429, %{}}})
      FakeSecondary.set_reply({:ok, %{"action" => "help"}})

      assert {:ok, %{"action" => "help"}} =
               Brain.LLM.Providers.Fallback.generate_structured("sys", "user", %{})
    end
  end

  describe "primary returns missing_api_key -> secondary succeeds" do
    test "falls back to secondary on missing API key" do
      FakePrimary.set_reply({:error, :missing_api_key})
      FakeSecondary.set_reply({:ok, %{"action" => "ignore"}})

      assert {:ok, %{"action" => "ignore"}} =
               Brain.LLM.Providers.Fallback.generate_structured("sys", "user", %{})
    end
  end

  describe "primary returns decode error -> secondary succeeds" do
    test "falls back to secondary on JSON decode failure" do
      FakePrimary.set_reply({:error, %Jason.DecodeError{}})
      FakeSecondary.set_reply({:ok, %{"action" => "add_items"}})

      assert {:ok, %{"action" => "add_items"}} =
               Brain.LLM.Providers.Fallback.generate_structured("sys", "user", %{})
    end
  end

  describe "both fail" do
    test "returns the last error" do
      FakePrimary.set_reply({:error, {:gemini_http_error, 500, %{}}})
      FakeSecondary.set_reply({:error, {:groq_http_error, 503, %{}}})

      assert {:error, {:groq_http_error, 503, %{}}} =
               Brain.LLM.Providers.Fallback.generate_structured("sys", "user", %{})
    end
  end

  describe "non-retryable primary error" do
    test "does NOT fall back to secondary" do
      FakePrimary.set_reply({:error, {:gemini_http_error, 400, %{}}})

      assert {:error, {:gemini_http_error, 400, %{}}} =
               Brain.LLM.Providers.Fallback.generate_structured("sys", "user", %{})
    end
  end

  describe "generate_menu/3" do
    test "primary succeeds" do
      FakePrimary.set_reply({:ok, %{"days" => []}})

      assert {:ok, %{"days" => []}} =
               Brain.LLM.Providers.Fallback.generate_menu("sys", "user", %{})
    end

    test "falls back to secondary on failure" do
      FakePrimary.set_reply({:error, %Req.TransportError{reason: :timeout}})
      FakeSecondary.set_reply({:ok, %{"days" => []}})

      assert {:ok, %{"days" => []}} =
               Brain.LLM.Providers.Fallback.generate_menu("sys", "user", %{})
    end
  end

  describe "generate_structured_with_media/4" do
    test "primary succeeds" do
      FakePrimary.set_reply({:ok, %{"products" => []}})

      assert {:ok, %{"products" => []}} =
               Brain.LLM.Providers.Fallback.generate_structured_with_media("sys", "user", %{}, %{mimetype: "image/jpeg", data: "abc"})
    end

    test "falls back to secondary on failure" do
      FakePrimary.set_reply({:error, {:gemini_http_error, 500, %{}}})
      FakeSecondary.set_reply({:ok, %{"products" => ["arroz"]}})

      assert {:ok, %{"products" => ["arroz"]}} =
               Brain.LLM.Providers.Fallback.generate_structured_with_media("sys", "user", %{}, %{mimetype: "image/jpeg", data: "abc"})
    end
  end

  describe "single provider chain" do
    test "uses only the one provider configured" do
      Application.put_env(:brain, :llm_fallback_chain, [FakePrimary])
      FakePrimary.set_reply({:ok, %{"action" => "help"}})

      assert {:ok, %{"action" => "help"}} =
               Brain.LLM.Providers.Fallback.generate_structured("sys", "user", %{})
    end

    test "returns error when single provider fails" do
      Application.put_env(:brain, :llm_fallback_chain, [FakePrimary])
      FakePrimary.set_reply({:error, :missing_api_key})

      assert {:error, :missing_api_key} =
               Brain.LLM.Providers.Fallback.generate_structured("sys", "user", %{})
    end
  end
end
