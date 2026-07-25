import Config

# Configure your database for testing
config :brain, Brain.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  database: "house_assistant_test#{System.get_env("MIX_TEST_PARTITION")}",
  port: String.to_integer(System.get_env("POSTGRES_PORT") || "5432"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2


# We don't run a server during test. If one is required,
# you can enable the server option below.
config :brain, BrainWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "59G2z7hbeGAsvIfvmEYEoYYoR92f74jwgWPBL5ywp8Jse5J58E/a2lVTSikgYNiC",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
