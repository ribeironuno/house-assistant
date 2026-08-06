# Brain — House Assistant Documentation

The Brain is an Elixir/Phoenix application that receives WhatsApp messages from the Bridge,
figures out what the user wants, does the work, and sends a reply back.

---

## How messages flow

```
WhatsApp group message
        │
        ▼
  ┌─────────────┐
  │    Bridge    │  whatsapp-web.js: receives the message,
  │  (Node.js)   │  forwards it to the Brain via HTTP POST.
  └──────┬──────┘
         │  POST /webhook/whatsapp
         │  { group_id, sender, text, media? }
         ▼
  ┌─────────────┐
  │    Brain     │  Elixir/Phoenix: classifies the command,
  │  (Elixir)    │  runs the logic, stores data, calls Gemini.
  └──────┬──────┘
         │  POST /send (via BridgeClient)
         │  { to: group_id, text: "[BOT] ..." }
         ▼
  ┌─────────────┐
  │    Bridge    │  Sends the reply back to the WhatsApp group.
  └─────────────┘
```

**Two layers of loop prevention** stop the bot from replying to its own messages:

1. The Bridge drops any message whose body starts with `[BOT]`, matches a recently-sent
   message ID, or matches recently-sent text (60-second window).
2. The Brain checks the `[BOT]` prefix again as a safety net.

---

## Command routing

When a text message arrives, `Brain.Commands.handle/3` tries to match it in order:

1. **Help** — `ajuda` / `help` / `comandos` → shows the full help text.
2. **Reminders** — starts with `lembrar de` / `lembra-me de` → `Brain.Reminders`.
3. **Shopping list** — `adiciona`, `remove`, `lista`, `limpar lista` → `Brain.ShoppingList`.
4. **LLM fallback** — anything else goes to `Brain.LLM.CommandInterpreter` which asks
   Gemini to classify the message into one of 14 known actions (see table below).

The LLM runs on every unmatched message and must stay fast (15-second timeout). The
classification prompt only receives the message text and current datetime — no pantry
history, no meal preferences, to keep costs low on the free tier.

If the action is `generate_menu` (which needs heavy context), a second, separate call is
made to Gemini with the full prompt (pantry, history, preferences, constraints, 120s timeout).

### Supported LLM actions

| Action | What the user says | What happens |
|--------|-------------------|--------------|
| `add_items` | "adiciona leite e pão" | Adds to **shopping list** |
| `remove_item` | "remove o leite" | Removes from shopping list |
| `list_items` | "lista" | Shows the shopping list |
| `clear_items` | "limpar lista" | Clears the shopping list |
| `set_reminder` | "lembrar de pagar scouts amanhã" | Creates a reminder |
| `add_pantry_items` | "tenho arroz, frango, atum" | Adds to **pantry** |
| `remove_pantry_item` | "usei o arroz" | Removes from pantry |
| `list_pantry` | "o que tenho na despensa?" | Shows pantry contents |
| `clear_pantry` | "limpar despensa" | Clears the pantry |
| `generate_menu` | "faz-me o menu da semana" | Generates a weekly dinner menu |
| `get_recipe` | "receita de terça" | Shows a stored recipe |
| `rate_meal` | "gostei do bacalhau" / "não gostei da feijoada" | Records preference |
| `help` | "ajuda" | Shows help text |
| `ignore` | "olá", jokes, unclear messages | No reply |

---

## Shopping list

**What it does:** A shared grocery list. Items are added when the user says so, removed
when purchased, and displayed as a numbered list.

**Database table:** `shopping_items` (name, added_by, done)

### Commands

| You say | What happens |
|---------|-------------|
| `adiciona leite, ovos, manteiga` | Adds three items |
| `remove o leite` | Removes the first match (case-insensitive substring) |
| `lista` / `ver lista` | Shows all active items in order |
| `limpar lista` | Deletes everything |

Items are matched by **substring** — "remove leite" finds "Leite Gordo" because "leite"
appears in the name.

### Invoice processing

When you send a **photo of a receipt**, the Brain:

1. Sends the image to Gemini (vision mode) and asks it to extract product names.
2. Matches each extracted name against your active shopping list using three strategies:
   - Exact match (after normalization).
   - Substring match (either direction).
   - Word overlap (ignoring Portuguese stop words: de, do, da, dos, das, e, em, para, com).
3. Deletes the matched items from the list.
4. Adds the purchased items to the pantry (skipping items already there), so
   "what I bought" becomes "what I have at home".
5. Reports what was removed from the list and what was added to the pantry, plus
   what was on the receipt but not on the list.

---

## Pantry (Despensa)

**What it does:** Tracks food items you already have at home. This context is used by
the menu planner to prefer dishes that use existing ingredients.

**Database table:** `pantry_items` (name, added_by)

### Commands

| You say | What happens |
|---------|-------------|
| `tenho arroz, frango, atum` | Adds all three items |
| `comprei natas` | Adds natas |
| `usei o arroz` | Removes the first match |
| `o que tenho na despensa?` | Shows pantry contents |
| `limpar despensa` | Clears everything |

The pantry context is injected into the menu generation prompt so Gemini knows
what ingredients are already available and what needs to be bought.

---

## Reminders

**What it does:** Stores a reminder with a specific datetime and sends it to the
group when it's time.

**Database table:** `reminders` (text, group_id, created_by, remind_at, sent_at)

### How it works

1. You say something like `lembrar de pagar scouts daqui a 3 dias`.
2. The Brain parses the time expression, computes a UTC datetime, stores it.
3. A GenServer (`Dispatcher`) polls every 30 seconds for due reminders.
4. When a reminder is due, it sends `[BOT] 🔔 Lembrete: pagar scouts` to the group.

### Time expressions (Portuguese)

| You say | Reminder fires at |
|---------|-------------------|
| `daqui a 30 minutos` | Now + 30 min |
| `daqui a 2 horas` | Now + 2 hours |
| `daqui a 3 dias` | Now + 3 days |
| `logo` | Today at 19:00 (or 21:00 if it's after 18:00) |
| `amanhã` | Tomorrow at 10:00 |
| `amanhã de manhã` | Tomorrow at 09:00 |
| `à sexta` | Next Friday at 10:00 |
| `às 18h` | Today (or next occurrence) at 18:00 |

---

## Weekly menu planner

**What it does:** Generates a 7-day dinner menu (tomorrow + 6 days) in Portuguese
cuisine style, with full recipes, respecting your pantry contents, past meals, and
learned preferences.

**Database tables:** `weekly_menus`, `meal_feedback`, `pantry_items` (reads pantry)

### The flow

```
"faz-me o menu da semana"
        │
        ▼
  LLM classifier → action: generate_menu, constraints: ""
        │
        ▼
  MenuPlanner.generate/2
        │
        ├── Pantry.get_all()            → what you have at home
        ├── MenuHistory.recent_meals()  → dishes from last 4 weeks
        ├── MealFeedback.summarize()    → likes and dislikes
        └── User constraints            → "quarta rápido", "4 doses"
        │
        ▼
  MenuPromptHelper.build/5 → heavy system prompt with all context
        │
        ▼
  Gemini (generate_menu, 120s timeout) → JSON with 7 days + full recipes
        │
        ▼
  Persisted to weekly_menus table
        │
        ▼
  Formatted summary reply sent to the group
```

### What the menu looks like

```
[BOT] 🍽️ Menu da Semana
Segunda-feira (03/08) — Frango assado com batatas
⏱ 45 min | 👥 4 doses

Terça-feira (04/08) — Bacalhau com natas
⏱ 60 min | 🛒 Precisa comprar: natas, bacalhau

...

🛒 Para comprar: natas, bacalhau, curgete

Diz "receita de terça" para veres o passo a passo.
```

### Menu rules baked into the prompt

- **Portuguese cuisine focus** — bacalhau, carne assada, sopas, arroz de pato, feijoada, etc.
- **No repeats** — dishes served in the last 4 weeks are excluded.
- **Protein variety** — no protein repeated more than twice per week.
- **Pantry-first** — prefers dishes using existing ingredients; the rest goes into `needs_to_buy`.
- **Full recipes always** — every day includes ingredients + steps (stored for `receita` lookup).
- **Constraints respected literally** — "quarta rápido" means low prep time on Wednesday.

### Recipes

When someone says `receita de terça` (or a dish name), the Brain reads the stored recipe
from the latest `weekly_menus` row — no new LLM call needed.

### Preference learning

After the menu is generated:

| You say | What happens |
|---------|-------------|
| `gostei do bacalhau` | Saved as a like |
| `não gostei da feijoada` | Saved as a dislike |

These likes/dislikes are injected into the next menu generation prompt as raw examples.
Gemini generalizes from them (e.g. "likes fish, dislikes heavy stews"). No scoring
system or embeddings — deliberately simple and debuggable.

---

## LLM layer

### Two separate prompts

1. **Classifier prompt** (`PromptHelper`) — lightweight, runs on every unmatched message.
   Receives only the message text and current datetime. Must be fast and cheap.
   Returns a structured JSON with the action name, relevant fields, and confidence score.

2. **Menu prompt** (`MenuPromptHelper`) — heavy, only called when the classifier
   resolves to `generate_menu`. Receives the full pantry, meal history, preferences,
   user constraints, and today's date. Runs with a 120-second timeout.

### Provider

Currently **Google Gemini** (Flash model, free tier). The provider is pluggable via
the `Brain.LLM.Provider` behaviour — any provider that implements `generate_structured/3`,
`generate_structured_with_media/4`, and `generate_menu/3` can be swapped in.

### Confidence threshold

Messages with a classification confidence below **0.65** are ignored. This prevents
the bot from reacting to ambiguous messages.

---

## Configuration

| Setting | Default | What it does |
|---------|---------|-------------|
| `GEMINI_API_KEY` | (none) | **Required.** Your Gemini API key. |
| `GEMINI_MODEL` | `gemini-flash-latest` | Which Gemini model to use. |
| `llm_command_interpreter_enabled` | `true` | Enables/disables the LLM classifier and invoice processor. |
| `menu_planner_enabled` | `true` | Enables/disables menu generation. |
| `send_outgoing_messages` | `true` | Master switch — when `false`, the Brain logs but never sends messages. |
| `reminder_dispatch_interval_ms` | `30000` | How often the reminder dispatcher polls (milliseconds). |
| `BRIDGE_SEND_URL` | `http://localhost:3000/send` | Where to send outgoing messages. |
| `TARGET_GROUP_ID` | (set in .env) | Which WhatsApp group the bot responds to. |

---

## Database tables

| Table | Purpose |
|-------|---------|
| `shopping_items` | Grocery list items (active or done) |
| `reminders` | Scheduled reminders with fire time |
| `pantry_items` | Food items currently at home |
| `weekly_menus` | Generated menus with full recipes (JSON) |
| `meal_feedback` | Like/dislike records per dish |

Tables are linked by `group_id` (WhatsApp group JID string). There are no foreign keys.

---

## Project structure

```
brain/
├── lib/
│   ├── brain.ex                        # Application entry
│   └── brain/
│       ├── application.ex              # Supervision tree
│       ├── repo.ex                     # Ecto repo
│       ├── commands.ex                 # Central command router
│       ├── shopping_list.ex            # Shopping list context
│       ├── shopping_list/
│       │   ├── item.ex                 # ShoppingItem schema
│       │   └── invoice_processor.ex    # Receipt image → auto-remove
│       ├── pantry.ex                   # Pantry context
│       ├── pantry/item.ex              # PantryItem schema
│       ├── reminders.ex                # Reminders context
│       ├── reminders/
│       │   ├── reminder.ex             # Reminder schema
│       │   └── dispatcher.ex           # GenServer: polls & sends due reminders
│       ├── meal_feedback.ex            # MealFeedback context
│       ├── menu_history.ex             # Reads past menus (avoids repeats)
│       ├── menu/
│       │   ├── weekly_menu.ex          # WeeklyMenu schema
│       │   └── meal_feedback.ex        # MealFeedback schema
│       ├── menu_planner.ex             # Generate menu, get recipe, format replies
│       └── llm/
│           ├── command_interpreter.ex   # Classifies messages into actions
│           ├── prompt_helper.ex         # Lightweight classifier prompt
│           ├── menu_prompt_helper.ex    # Heavy menu-generation prompt
│           └── provider/
│               ├── provider.ex          # LLM provider behaviour
│               └── gemini.ex            # Google Gemini implementation
│   └── brain_web/
│       ├── router.ex                   # Single route: POST /webhook/whatsapp
│       └── controllers/
│           └── webhook_controller.ex   # Receives webhooks, dispatches to Brain
├── priv/repo/migrations/               # 5 migrations (tables above)
├── test/                               # 80 tests
├── config/                             # Config files
└── mix.exs                             # Dependencies
```

---

## How to run

```bash
# Start the database
docker compose up -d db

# Setup and migrate
mix ecto.setup

# Run tests
mix test

# Start the server (local development)
mix phx.server
```

The Bridge must be running separately (`cd bridge && npm start` or `docker compose up bridge`).
