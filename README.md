# House Assistant - WhatsApp Family Bot

A self-hosted WhatsApp assistant for the family group. It runs a shared **shopping list**,
**scheduled reminders**, a **pantry** inventory, and a **weekly menu planner** backed by
Postgres, and it understands commands in **Portuguese**. It can even **read receipt photos**
and remove bought items from the shopping list automatically.

---

## Important disclaimers

### Personal use only

This project is designed for **personal, non-commercial use**. It is not intended to be
sold, offered as a service, or used in any production/commercial context. The data stored
in the database is **not encrypted at rest**, it sits in plain Postgres rows accessible
to anyone with database access. This makes it unsuitable for handling sensitive data
beyond a household's own grocery lists and meal plans.

### WhatsApp account

The bot runs on the **same WhatsApp account as the user**. There is no need for a
separate SIM card or phone number, the bot connects via the same WhatsApp Web session
your phone uses. However, using a **dedicated SIM/phone is recommended** for a better
experience, since the bot's activity (sending messages, receipts, etc.) will appear in
your own WhatsApp alongside your personal chats. If you use the same account, the bot is
prepared to **ignore its own messages** to prevent loops.

### First run, QR code linking

On first run, the Bridge prints a **QR code** in the terminal. You must scan it with your
phone (WhatsApp > Linked Devices > Link a Device). This is because the Bridge uses
[whatsapp-web.js](https://github.com/pedroslopez/whatsapp-web.js), which runs an
**embedded Chromium browser via Puppeteer** to simulate the WhatsApp Web client. The QR
scan authenticates this browser session against WhatsApp's servers.

### Language

The bot understands **Portuguese only**. All commands, replies, and natural language
processing are written in PT. There is no translation or multi-language support.

### LLM provider

The only supported LLM is **Google Gemini** (Flash model, free tier). No other providers
are supported. A `GEMINI_API_KEY` is required for the LLM features (classifier, receipt
processing, menu generation) to work.

### Group approval flow

When the bot is added to a WhatsApp group, it does **not** start responding immediately.
Instead, it registers the group as `waiting_approval` and stays silent. The owner must
then go to the **backoffice** (`http://localhost:4000/backoffice`), log in, and manually
approve the group. This is a safety measure to prevent the bot from spamming organic
groups it gets added to.

Once approved, the group becomes `pending`. The bot sends an intro message asking
"Queres que fique ativo neste grupo? Responde sim ou nao." Someone in the group must
reply **"sim"** to activate the bot. After that, the bot processes messages normally.

The backoffice also lets you block, unblock, or delete groups, and manage admin numbers
per group (admins can run `limpar` commands that affect everyone's data).

---

## Features

| Feature | What it does |
|---|---|
| **Shopping list** | Add, remove, list and clear items with plain Portuguese commands |
| **Reminders** | "lembrar de pagar scouts daqui a 3 dias" posts the reminder at the right time |
| **Receipt photos** | Send a photo of a supermarket receipt, Gemini extracts the products, bought items are removed from the list and added to the pantry |
| **Pantry** | Track what's at home ("tenho arroz, frango") |
| **Weekly menu** | "faz-me o menu da semana" gives 7 days of dinner ideas and recipes, using your pantry and taste preferences |
| **LLM fallback** | Any unrecognised message is classified by Gemini into one of 14 actions, so natural phrasing works |

---

## Real-life use cases

**The shopping list that fixes itself**

Maria notices at work that the milk is about to run out. She texts `adiciona leite, pao e
manteiga`. Later, at the supermarket, her husband sends `lista`, buys everything, and
snaps a photo of the receipt. The bot matches the items, removes them from the list, and
adds them to the pantry. Next time someone opens the list, it's already clean.

**Bills and commitments you never forget**

`lembrar de pagar a luz daqui a 3 dias` posts a reminder to the group on the right day.

**Dinners planned from what's in the cupboard**

After the shop, the pantry knows what's at home (`tenho frango, arroz, tomate`). Send
`faz-me o menu da semana` and get 7 days of dinner ideas with recipes that prefer those
ingredients. When a dish misses the mark, `nao gostei da feijoada` teaches it your taste
for next week.

---

## Architecture

```
+---------------------+   whatsapp-web.js   +---------------------------+
|   WhatsApp Group    | <-----------------> |  Bridge (Node.js)         |
+---------------------+                     +------------+--------------+
                                             |  POST /webhook/whatsapp (incoming)
                                             |  POST /send (outgoing)
                                             v
                                  +---------------------------+
                                  |  Brain (Elixir / Phoenix) |
                                  |  commands + LLM (Gemini)  |
                                  +------------+--------------+
                                             |  SQL (Ecto)
                                             v
                                  +---------------------------+
                                  |  PostgreSQL (Docker)      |
                                  +---------------------------+
```

### Components

| Service | Tech | Role |
|---|---|---|
| **Bridge** | Node.js + whatsapp-web.js | Speaks the WhatsApp Web protocol. Forwards incoming group messages to the Brain via `POST /webhook/whatsapp` and sends replies back via `POST /send`. No business logic. |
| **Brain** | Elixir / Phoenix | Receives messages, classifies commands (rule-based first, LLM fallback), reads/writes Postgres, schedules reminders, calls Gemini for invoices/menus, and replies via the bridge. |
| **DB** | PostgreSQL 16 | Stores shopping list, reminders, pantry, menus and meal feedback. Managed by Ecto migrations. |


---

## How messages are handled

1. A message arrives at the Bridge (`message_create` event).
2. The Bridge drops bot echoes (loop prevention) and forwards the rest to the Brain.
3. The Brain checks the group's status in the database. If it's not `active`, the
   message is ignored.
4. The Brain tries in order:
   - **Explicit commands** (`adiciona`, `remove`, `lista`, `lembrar`, `ajuda`, ...)
   - **LLM classifier** (Gemini maps any other message to one of 14 actions)
5. The Brain replies with a `[BOT]` prefixed message via the bridge.

---

## Loop Prevention

The bridge and the owner's phone share the same WhatsApp account, so every bot reply also
fires a `message_create` event. Two independent layers prevent infinite loops:

1. **Bridge** (`isBridgeSelfMessage()`) drops messages that start with `[BOT]`, match a
   recently-sent message ID, or match recently-sent text (60-second window).
2. **Brain** (`Brain.Commands.handle/3`) checks the `[BOT]` prefix again as a safety net.

All bot replies are prefixed `[BOT]` (e.g. `[BOT] Adicionado: leite`).

> **Note on `fromMe` messages**: whatsapp-web.js swaps `message.from` / `message.to` for
> self-sent messages. The bridge resolves the real group ID as `message.fromMe ? message.to : message.from`.

---

## Commands (Portuguese)

The assistant is case-insensitive and silently ignores unrecognised messages.

### Shopping list

| Command | Example | Bot reply |
|---|---|---|
| `adiciona <item>[, <item>]` | `adiciona leite, pao, manteiga` | `[BOT] Adicionados:\n1. leite\n2. pao\n3. manteiga` |
| `remove <item>` | `remove leite` | `[BOT] Removido: leite` |
| `lista` / `ver lista` | `lista` | `[BOT] Lista de Compras:\n1. leite\n...` |
| `limpar lista` / `limpar compras` | `limpar lista` | `[BOT] Lista de compras limpa.` |

Items are matched by substring, `remove leite` also removes `Leite Gordo`.

### Reminders

| Command | Example | Fires at |
|---|---|---|
| `lembrar de <tarefa> daqui a N minutos/horas/dias/semanas` | `lembrar de pagar scouts daqui a 3 dias` | Now + N units |
| `lembra-me de <tarefa> amanha` | `lembra-me de pagar a agua amanha` | Tomorrow at 10:00 |
| `lembrar de <tarefa> logo` | `lembrar de fazer isto logo` | Today at 19:00 (21:00 after 18:00) |
| `lembrar de <tarefa> a sexta` / `as 18h` | `lembrar de ligar a avo a sexta` | Next occurrence |
| `limpar lembretes` | `limpar lembretes` | Deletes all pending reminders |

Due reminders are posted back to the group as `[BOT] Lembrete: <tarefa>`.

### Clearing everything

| Command | Example | What happens |
|---|---|---|
| `limpar tudo` | `limpar tudo` | Clears shopping list, pantry, and reminders in one command |

### Pantry and menu

| Command | Example | What happens |
|---|---|---|
| `tenho <item>[, <item>]` / `comprei <item>` | `tenho arroz, frango` | Adds to pantry |
| `usei <item>` | `usei o arroz` | Removes from pantry |
| `o que tenho na despensa?` | `o que tenho na despensa?` | Shows pantry contents |
| `faz-me o menu da semana` | `faz-me o menu da semana` | Generates a 7-day dinner menu and recipes |
| `faz-me o menu da semana [regras]` | `faz-me o menu da semana so de carne` | Menu respecting user constraints |
| `receita de <dia>` | `receita de terca` | Shows the stored recipe for that day |
| `gostei de <prato>` / `nao gostei de <prato>` | `nao gostei da feijoada` | Records a preference for future menus |

### Help

`ajuda` / `help` / `comandos` lists the known commands.

---

## Receipt photos

Send a **photo of a supermarket receipt** and the bot will:

1. Send the image to Gemini (vision) and extract the product names.
2. Match them against your active shopping list:
   * exact and substring match first (free),
   * then one LLM call for semantically different names (e.g. list has `piripiri`, receipt says `tabasco chipotle`).
3. Delete the bought items from the list.
4. Add the bought items to your pantry (skipping items already there), so what you
   bought becomes what you have at home.
5. Reply with what was removed from the list and added to the pantry.

No extra command is needed, just send the photo to the group.

---

## Prerequisites

* [Docker Engine & Docker Compose](https://docs.docker.com/get-docker/)
* [Elixir 1.15+](https://elixir-lang.org/) and [Node.js 20+](https://nodejs.org/) (dev mode only)
* A [Google Gemini API key](https://aistudio.google.com/app/apikey) (free tier), required for the LLM features

---

## Running locally (recommended)

Only Postgres runs in Docker. The bridge and brain run directly on your machine.

### 1. Configure

```bash
cp .env.example .env
export GEMINI_API_KEY=your_key
```

### 2. Start Postgres

```bash
docker compose up -d db
```

### 3. Set up and start the Brain

```bash
cd brain
mix deps.get
mix ecto.setup
mix phx.server
```

### 4. Start the Bridge

```bash
cd bridge
npm install
node index.js             # scan the QR code on first run
```

---

## Environment variables

### Bridge

| Variable | Default | Description |
|---|---|---|
| `PORT` | `3000` | Port the bridge HTTP server listens on |
| `ELIXIR_WEBHOOK_URL` | `http://localhost:4000/webhook/whatsapp` | Where to forward incoming messages |
| `BRIDGE_AUTH_TOKEN` | *(empty, no auth, dev only)* | Shared secret for the brain's /send and /leave calls |

### Brain

| Variable | Default | Description |
|---|---|---|
| `GEMINI_API_KEY` | *(none, required)* | Google Gemini API key |
| `GEMINI_MODEL` | `gemini-flash-latest` | Which Gemini model to use |
| `BRIDGE_SEND_URL` | `http://localhost:3000/send` | Bridge endpoint for outgoing messages |
| `BRIDGE_LEAVE_URL` | `http://localhost:3000/leave` | Bridge endpoint for leaving a group |
| `DATABASE_URL` | *(from config)* | Postgres connection string |
| `PHX_SERVER` | | Set to `true` in Docker to auto-start the server |

Copy `.env.example` to `.env` and optionally set `BRIDGE_AUTH_TOKEN`.

---

## Database

### Dev migrations

```bash
cd brain
mix ecto.create
mix ecto.migrate
mix ecto.reset
```

### Tables

| Table | Purpose |
|---|---|
| `shopping_items` | Grocery list items |
| `reminders` | Scheduled reminders with fire time |
| `pantry_items` | Food items currently at home |
| `weekly_menus` | Generated menus with full recipes (JSON) |
| `meal_feedback` | Like/dislike records per dish |

### Inspect directly

```bash
docker exec -it whatsapp_db psql -U postgres -d house_assistant_dev
```

```sql
SELECT id, name, added_by, done FROM shopping_items;
SELECT id, text, group_id, remind_at, sent_at FROM reminders ORDER BY remind_at;
```

---

## Tests

```bash
cd brain
mix test
```

Tests cover command parsing, DB persistence, webhook routing, invoice matching,
LLM classification and menu generation. LLM calls are stubbed in tests, they never hit
the network or spend tokens.

---

## Project layout

```
house_assistant/
+-- bridge/        # Node.js whatsapp-web.js bridge (src/ split into modules)
+-- brain/         # Elixir / Phoenix application
|   +-- lib/       # commands, shopping list, pantry, reminders, menu, LLM providers
|   +-- test/      # ExUnit test suite
|   +-- DOCS.md    # detailed architecture & feature documentation
+-- docker-compose.yml
+-- .env.example
```
