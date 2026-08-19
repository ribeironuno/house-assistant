# Brain

Elixir/Phoenix application that powers the House Assistant WhatsApp bot. It receives
messages from the Bridge, classifies commands, reads/writes Postgres, calls Google Gemini
for LLM features, and replies through the Bridge.

> **Personal use only.** Data in the database is not encrypted at rest.
> Portuguese only. LLM calls use a Gemini + Groq fallback chain.

## How it works

```
POST /webhook/whatsapp (from Bridge)
        |
        v
  WebhookController        # validates token, rate-limits, dispatches command
        |
        v
  Commands.handle/3        # rule-based match first, LLM fallback via Gemini
        |
        v
  BridgeClient.send        # POST /send to Bridge -> WhatsApp group
```

1. The Bridge POSTs incoming WhatsApp messages to `POST /webhook/whatsapp`.
2. The WebhookController validates the auth token, rate-limits, and dispatches
   the message to `Commands.handle/3`.
3. `Commands.handle/3` tries rule-based matching first (explicit prefixes like
   `adiciona`, `remove`, `lista`, `lembrar`, `ajuda`), then falls back to the
   LLM classifier (Gemini) which maps the message to one of 14 actions.
4. The Brain replies by POSTing to the Bridge's `/send` endpoint.

## Group approval flow

When the bot is added to a new group, it registers as `waiting_approval` and stays
silent. The owner must go to the **backoffice** (`/backoffice`), log in, and manually
approve the group. Only then does the bot send its intro message and ask the group to
activate it by replying "sim".

This is a safety measure. Since the bot can run on the same WhatsApp account as the
owner, it needs to be prevented from responding in organic groups where it was added
accidentally or by someone else.

The backoffice also supports:
* Approving, blocking, unblocking, and deleting groups
* Managing admin numbers per group (admins can run `limpar` commands)

## Project structure

```
brain/
+-- lib/
|   +-- brain.ex                        # Application entry
|   +-- brain/
|   |   +-- application.ex              # OTP supervision tree
|   |   +-- repo.ex                     # Ecto repo (Postgres)
|   |   +-- commands.ex                 # Central command router
|   |   +-- shopping_list.ex            # Shopping list context (add, remove, list, clear)
|   |   +-- shopping_list/
|   |   |   +-- item.ex                 # ShoppingItem Ecto schema
|   |   |   +-- invoice_processor.ex    # Receipt image -> Gemini vision -> auto-remove + pantry
|   |   +-- pantry.ex                   # Pantry context (add, remove, list, clear)
|   |   +-- pantry/item.ex              # PantryItem Ecto schema
|   |   +-- reminders.ex                # Reminders context (schedule, clear)
|   |   +-- reminders/
|   |   |   +-- reminder.ex             # Reminder Ecto schema
|   |   |   +-- dispatcher.ex           # GenServer: polls every 30s, sends due reminders
|   |   +-- meal_feedback.ex            # Like/dislike tracking
|   |   +-- menu_history.ex             # Reads past menus (avoids repeats)
|   |   +-- menu/
|   |   |   +-- weekly_menu.ex          # WeeklyMenu Ecto schema
|   |   |   +-- meal_feedback.ex        # MealFeedback Ecto schema
|   |   +-- menu_planner.ex             # Generate weekly menu, get recipe, format replies
|   |   +-- groups.ex                   # Multi-group activation (waiting_approval -> pending -> active)
|   |   +-- groups/group.ex             # Group Ecto schema
|   |   +-- processed_message.ex        # Idempotency: tracks processed message IDs
|   |   +-- text.ex                     # Text normalization helpers
|   |   +-- whatsapp/
|   |   |   +-- bridge_client.ex        # HTTP client for Bridge /send and /leave
|   |   +-- llm/
|   |       +-- command_interpreter.ex  # Classifies messages into 14 actions via Gemini
|   |       +-- prompt_helper.ex        # Lightweight classifier system prompt
|   |       +-- menu_prompt_helper.ex   # Heavy menu-generation system prompt
|   |       +-- provider/
|   |           +-- provider.ex         # LLM provider behaviour
|   |           +-- gemini.ex           # Google Gemini implementation
|   +-- brain_web/
|       +-- endpoint.ex                 # Phoenix endpoint
|       +-- router.ex                   # Routes: /webhook/whatsapp, /backoffice
|       +-- controllers/
|       |   +-- webhook_controller.ex   # Receives bridge webhooks, dispatches commands
|       |   +-- backoffice_*            # Backoffice LiveView auth/controllers
|       +-- live/
|           +-- backoffice_live.ex      # Admin dashboard (LiveView): approve/block/delete groups
+-- priv/repo/migrations/               # Ecto migrations
+-- test/                               # ExUnit test suite (LLM calls stubbed)
+-- config/                             # Config files per environment
+-- mix.exs                             # Dependencies
+-- DOCS.md                             # Full documentation
```

## LLM layer

Two separate prompts, both hitting LLM providers via a fallback chain (Gemini first,
Groq second):

1. **Classifier** (`PromptHelper`) is lightweight and runs on every unmatched message.
   Receives only the message text and current datetime. Returns a structured JSON
   with the action, relevant fields, and confidence score. Must be fast (15s timeout).
   Messages below 0.65 confidence are ignored.

2. **Menu generator** (`MenuPromptHelper`) is heavy and only called when the classifier
   resolves to `generate_menu`. Receives full pantry, meal history, preferences,
   and user constraints. Runs with a 120-second timeout.

If the primary provider (Gemini) fails with a retryable error (timeout, 429, 5xx,
network error), the request is automatically retried against Groq.

### Supported LLM actions

| Action | Example user input |
|--------|-------------------|
| `add_items` | "adiciona leite e pao" |
| `remove_item` | "remove o leite" |
| `list_items` | "lista" |
| `clear_items` | "limpar lista" |
| `set_reminder` | "lembrar de pagar scouts amanha" |
| `add_pantry_items` | "tenho arroz, frango, atum" |
| `remove_pantry_item` | "usei o arroz" |
| `list_pantry` | "o que tenho na despensa?" |
| `clear_pantry` | "limpar despensa" |
| `generate_menu` | "faz-me o menu da semana" |
| `get_recipe` | "receita de terca" |
| `rate_meal` | "gostei do bacalhau" / "nao gostei da feijoada" |
| `help` | "ajuda" |
| `ignore` | jokes, unclear messages |

## Database

### Tables

| Table | Purpose |
|-------|---------|
| `groups` | WhatsApp group registration (activation status) |
| `shopping_items` | Grocery list items, scoped per group |
| `reminders` | Scheduled reminders with fire time |
| `pantry_items` | Food items at home, scoped per group |
| `weekly_menus` | Generated menus with full recipes (JSON) |
| `meal_feedback` | Like/dislike records per dish |

All tables are scoped by `group_id` (WhatsApp group JID string).

### Migrations

```bash
mix ecto.create    # create database
mix ecto.migrate   # run migrations
mix ecto.reset     # drop + recreate + migrate
```

## Running locally

```bash
# Start Postgres (from project root)
docker compose up -d db

# Setup and migrate
mix deps.get
mix ecto.setup

# Start server
mix phx.server        # http://localhost:4000

# Run tests (LLM calls stubbed, no network)
mix test
```

The Bridge must be running separately (`cd bridge && node index.js`).

## Configuration

| Setting | Default | What it does |
|---------|---------|-------------|
| `GEMINI_API_KEY` | *(none, required)* | Google Gemini API key |
| `GEMINI_MODEL` | `gemini-flash-latest` | Which Gemini model to use |
| `GROQ_API_KEY` | *(none, recommended)* | Groq API key (fallback provider) |
| `GROQ_MODEL` | `llama-3.3-70b-versatile` | Groq model for text classification |
| `GROQ_VISION_MODEL` | `llama-4-scout-17b-16e-instruct` | Groq model for vision/receipt OCR |
| `WEBHOOK_SECRET` | *(none, required)* | Shared secret for verifying incoming webhooks from the Bridge |
| `BRIDGE_AUTH_TOKEN` | *(empty, no auth)* | Shared secret the Brain uses when calling the Bridge's `/send` and `/leave` endpoints |
| `SECRET_KEY_BASE` | *(none, required in prod)* | Phoenix secret for sessions/cookies (64+ bytes). Generate with `mix phx.gen.secret` |
| `BACKOFFICE_USER` | *(none, required)* | Backoffice login username |
| `BACKOFFICE_PASS_HASH` | *(none, required)* | Bcrypt hash of the backoffice password. Generate with `Bcrypt.hash_pwd_salt("your_password")` |
| `llm_command_interpreter_enabled` | `true` | Enables/disables the LLM classifier |
| `menu_planner_enabled` | `true` | Enables/disables menu generation |
| `send_outgoing_messages` | `true` | Master switch for outgoing messages |
| `reminder_dispatch_interval_ms` | `30000` | Reminder dispatcher poll interval |

## Dependencies

* **Phoenix** 1.8, web framework
* **Ecto** + **Postgrex**, database
* **Req**, HTTP client (for Gemini API and Bridge calls)
* **bcrypt_elixir**, backoffice auth

## Tests

```bash
mix test
```

88 tests covering command parsing, DB persistence, webhook routing, invoice matching,
LLM classification, and menu generation. LLM calls are stubbed, no network, no tokens.
