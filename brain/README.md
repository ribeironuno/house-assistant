# Brain

Elixir/Phoenix application that powers the House Assistant WhatsApp bot. It receives
messages from the Bridge, classifies commands, reads/writes Postgres, calls Google Gemini
for LLM features, and replies through the Bridge.

See the root [`README.md`](../README.md) for setup and the full feature list.

## Documentation

Detailed documentation lives in **[`DOCS.md`](DOCS.md)**: message flow, command routing,
every feature (shopping list, receipts, pantry, reminders, menu planner), the LLM layer,
configuration, and the module layout.

## Quick start

```bash
mix setup
mix phx.server        # or: iex -S mix phx.server
```

The server listens on `http://localhost:4000`. The Bridge posts incoming WhatsApp
messages to `POST /webhook/whatsapp`.

## Tests

```bash
mix test              # 88 tests — LLM calls are stubbed, no network / tokens
```
