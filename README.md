# 🏠 House Assistant — WhatsApp Family Bot

A self-hosted WhatsApp assistant for the family group. It manages a shared **shopping list** and scheduled **reminders** backed by Postgres, understands commands in **Portuguese**, and is designed to be extended with menus and an LLM layer in future phases.

---

## Architecture

```
┌─────────────────────┐        Baileys protocol        ┌───────────────────────┐
│   WhatsApp Group    │ ◄─────────────────────────────► │   Bridge (Node.js)    │
└─────────────────────┘                                 └──────────┬────────────┘
                                                                   │
                                              POST /webhook  │  POST /send
                                              (incoming)     │  (outgoing)
                                                             ▼
                                                  ┌───────────────────────┐
                                                  │   Brain (Elixir /     │
                                                  │   Phoenix + Ecto)     │
                                                  └──────────┬────────────┘
                                                             │  SQL (Ecto)
                                                             ▼
                                                  ┌───────────────────────┐
                                                  │   PostgreSQL (Docker) │
                                                  └───────────────────────┘
```

### Components

| Service | Tech | Role |
|---|---|---|
| **Bridge** | Node.js + whatsapp-web.js | Speaks the WhatsApp Web protocol. Forwards incoming group messages to the brain via `POST /webhook/whatsapp`. Sends replies back via `POST /send`. Has no intelligence of its own. |
| **Brain** | Elixir / Phoenix | Receives messages, parses commands, reads/writes Postgres, schedules due reminders, and calls the bridge to reply. All business logic lives here. |
| **DB** | PostgreSQL 16 | Stores the shopping list (`shopping_items` table) and reminders (`reminders` table). Managed by Ecto migrations. |

---

## Loop Prevention

Because the bridge and the owner's phone share the same WhatsApp account, every bot reply also fires a `message_create` event. The system avoids infinite loops at two independent layers:

1. **Bridge** — `isBridgeSelfMessage()` checks if the incoming message body starts with `[BOT]` and drops it immediately, before forwarding to the brain.
2. **Brain** — `Brain.Commands.handle/2` checks the same prefix and returns `:ignore`, so even if a bot echo slips through, it is never acted on.

All bot replies are prefixed with `[BOT]` (e.g. `[BOT] ✅ Adicionado: leite`).

> **Note on `fromMe` messages**: whatsapp-web.js swaps `message.from` / `message.to` for self-sent messages. The bridge resolves the real group ID as `message.fromMe ? message.to : message.from` before forwarding.

---

## Commands (Portuguese)

The assistant is case-insensitive and ignores all unrecognised messages silently.

| Command | Example | Bot reply |
|---|---|---|
| `adiciona <item>` / `adicionar <item>` | `adiciona leite` | `[BOT] ✅ Adicionado: leite` |
| `remove <item>` / `remover <item>` | `remove leite` | `[BOT] 🗑️ Removido: leite` |
| `lista` / `ver lista` / `mostrar lista` | `lista` | `[BOT] 🛒 Lista de Compras:\n1. leite\n...` |
| `limpar` / `limpar lista` | `limpar lista` | `[BOT] 🧹 Lista de compras limpa.` |
| `lembrar de <tarefa> logo` | `lembrar de fazer isto logo` | `[BOT] 🔔 Lembrete guardado: fazer isto (...)` |
| `lembrar de <tarefa> daqui a N minutos/horas/dias/semanas` | `lembrar de pagar scouts daqui a 3 dias` | `[BOT] 🔔 Lembrete guardado: pagar scouts (...)` |
| `lembra-me de <tarefa> amanhã` | `lembra-me de pagar a água amanhã` | `[BOT] 🔔 Lembrete guardado: pagar a água (...)` |
| `ajuda` / `help` / `comandos` | `ajuda` | Lista os comandos conhecidos |

Due reminders are sent back to the original WhatsApp group as `[BOT] 🔔 Lembrete: <tarefa>`.

---

## Prerequisites

- [Docker Engine & Docker Compose](https://docs.docker.com/get-docker/)
- [Elixir 1.15+](https://elixir-lang.org/) & [Node.js 20+](https://nodejs.org/) (dev mode only)

---

## Running Locally (recommended)

Only Postgres runs in Docker. The bridge and brain run directly on your machine — faster iteration, no rebuild needed.

### 1. Start Postgres

```bash
docker compose up -d db
```

### 2. Set up & start the Brain

```bash
cd brain
mix deps.get
mix ecto.setup      # creates DB + runs migrations
```

Then start it in your preferred way (e.g. `iex -S mix phx.server`).

### 3. Start the Bridge

```bash
cd bridge
npm install
```

Then start it (e.g. `node index.js`). Scan the QR code on first run.

---

## Running with Docker Compose (full stack)

Builds and runs all three services in containers:

```bash
docker compose up --build
```

---

## Environment Variables

### Bridge

| Variable | Default | Description |
|---|---|---|
| `PORT` | `3000` | Port the bridge HTTP server listens on |
| `ELIXIR_WEBHOOK_URL` | `http://localhost:4000/webhook/whatsapp` | Where to forward incoming messages |
| `TARGET_GROUP_ID` | *(empty — accept all)* | WhatsApp group JID to filter messages (e.g. `120363...@g.us`) |

### Brain

| Variable | Default | Description |
|---|---|---|
| `BRIDGE_SEND_URL` | `http://localhost:3000/send` | Bridge endpoint for outgoing messages |
| `REMINDER_DISPATCH_INTERVAL_MS` | `60000` | Reminder polling interval, if configured in Elixir runtime |
| `DATABASE_URL` | *(from config/dev.exs)* | Postgres connection string |
| `PHX_SERVER` | — | Set to `true` in Docker to auto-start the server |

Copy `.env.example` to `.env` and fill in `TARGET_GROUP_ID` for your family group.

---

## Database

### Dev migrations

```bash
cd brain
mix ecto.create    # create database
mix ecto.migrate   # run migrations
mix ecto.reset     # drop + recreate + migrate
```

### Inspect directly

```bash
docker exec -it whatsapp_db psql -U postgres -d house_assistant_dev
```

```sql
SELECT id, name, added_by, done, inserted_at FROM shopping_items;
SELECT id, text, group_id, remind_at, sent_at FROM reminders ORDER BY remind_at;
```

---

## Tests

```bash
cd brain
mix test
```

15 tests covering command parsing, DB persistence, and webhook routing.

---

## Roadmap

- [x] Phase 1 — WhatsApp bridge + Phoenix webhook plumbing
- [x] Phase 2 — Persistent shopping list with Postgres, Portuguese commands
- [x] Phase 3 — Dynamic reminders (e.g. "lembrar de pagar scouts daqui a 3 dias")
- [ ] Phase 4 — LLM intent parsing (Groq / Gemini free tier)
- [ ] Phase 5 — Weekly menu suggestions
- [ ] Phase 6 — Reminder parser improvements for exact dates/times
