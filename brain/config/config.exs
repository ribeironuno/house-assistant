# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :brain,
  ecto_repos: [Brain.Repo],
  generators: [timestamp_type: :utc_datetime],
  webhook_secret: nil,
  bridge_auth_token: nil

# Configures the endpoint
config :brain, BrainWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: BrainWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Brain.PubSub,
  live_view: [signing_salt: "PpCQSFeo"]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :brain, llm_provider: Brain.LLM.Providers.Gemini

# Oban configuration
config :brain, Oban,
  repo: Brain.Repo,
  queues: [default: 10, commands: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: {14, :days}, max_len: 1000},
    Oban.Plugins.DynamicQueues
  ]

# Hammer rate limiting configuration
config :hammer,
  backend: {Hammer.Backend.ETS, expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
