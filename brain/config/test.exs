import Config

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
