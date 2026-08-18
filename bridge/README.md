# Bridge

Node.js service that speaks the **WhatsApp Web** protocol via
[whatsapp-web.js](https://github.com/pedroslopez/whatsapp-web.js). It receives
incoming group messages and forwards them to the Brain (Elixir) over HTTP, then
sends the Brain's replies back to WhatsApp.

The Bridge contains **no business logic**, it is a thin transport layer.

> **Personal use only.** This shares the owner's personal WhatsApp account.
> Messages are forwarded in plain text with no encryption.

## How it works

1. On first start, the Bridge prints a **QR code** in the terminal.
2. Open WhatsApp on the owner's phone, **Linked Devices**, scan the QR code.
3. Once linked, the Bridge listens for group messages and forwards them to the Brain
   via `POST /webhook/whatsapp`.
4. The Brain replies via `POST /send` to the Bridge, which sends them back to WhatsApp.

## Project structure

```
bridge/
+-- index.js                 # Entry point: initializes whatsapp-web.js Client,
|                            #   sets up event handlers, starts HTTP server
+-- load-env.js              # Loads .env via dotenv (ESM compatibility)
+-- src/
|   +-- config.js            # Environment variables (PORT, WEBHOOK_URL, AUTH_TOKEN)
|   +-- handler.js           # handleIncomingMessage(): drops self-msgs, extracts
|   |                        #   media, forwards to Brain via POST webhook
|   |                        # handleGroupJoin(): notifies Brain when bot is added
|   +-- server.js            # Express server: /health, /send (Bearer auth), /leave
|   +-- loop-prevention.js   # Tracks sent message IDs/texts to prevent bot loops
|   +-- media-download.js    # Downloads image/document media from WhatsApp
|   +-- message-keys.js      # Helper for message ID extraction
+-- patches/                 # Local patch for whatsapp-web.js 1.34.7
|                            #   (July 2026 WhatsApp Web API change)
+-- Dockerfile
+-- .env.example
+-- package.json
```

## Loop prevention

The Bridge and the owner's phone share the same WhatsApp account, so every bot reply
also fires a `message_create` event. The Bridge drops messages that:

* Start with `[BOT]`
* Match a recently-sent message ID
* Match recently-sent text (60-second window)

All bot replies are prefixed `[BOT]` so the Bridge can identify them.

## HTTP endpoints

| Method | Path      | Auth         | Description                    |
| ------ | --------- | ------------ | ------------------------------ |
| `GET`  | `/health` | none         | Returns connection status      |
| `POST` | `/send`   | Bearer token | Send a text message to a group |
| `POST` | `/leave`  | Bearer token | Leave a WhatsApp group         |

## Setup

```bash
npm install
node index.js
```

## Environment variables

| Variable             | Default                                  | Description                                          |
| -------------------- | ---------------------------------------- | ---------------------------------------------------- |
| `PORT`               | `3000`                                   | Port the bridge HTTP server listens on               |
| `ELIXIR_WEBHOOK_URL` | `http://localhost:4000/webhook/whatsapp` | Where to forward incoming messages                   |
| `BRIDGE_AUTH_TOKEN`  | *(empty, no auth, dev only)*             | Shared secret for the brain's /send and /leave calls |

## Patching whatsapp-web.js

A July 2026 WhatsApp Web update broke `downloadMedia()` and other ID-keyed calls in
the pinned version (1.34.7). `npm install` applies a local patch via `patch-package`
(`bridge/patches/`), no manual step needed. Remove the patch once upstream ships a
release containing the fix.
