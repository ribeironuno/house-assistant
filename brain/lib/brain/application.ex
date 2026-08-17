defmodule Brain.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        BrainWeb.Telemetry,
        Brain.Repo,
        {DNSCluster, query: Application.get_env(:brain, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Brain.PubSub},
        oban_child(),
        reminder_dispatcher_child(),
        # Start to serve requests, typically the last entry
        BrainWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Brain.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BrainWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp oban_child do
    case Application.get_env(:brain, Oban) do
      config when is_list(config) ->
        {Oban, Keyword.merge(config, name: Brain.Oban)}

      nil ->
        {Oban, name: Brain.Oban}
    end
  end

  defp reminder_dispatcher_child do
    if Application.get_env(:brain, :start_reminder_dispatcher, true) do
      Brain.Reminders.Dispatcher
    end
  end
end
