# WhatsApp Family Assistant — Phase 1 (Plumbing)

Phase 1 provides basic two-way communication between WhatsApp and an Elixir/Phoenix service using a Node.js Baileys bridge.

## Prerequisites

- [Docker Engine & Docker Compose](https://docs.docker.com/get-docker/)

## Quick Start Guide

### 1. Launch Services

Start the services with Docker Compose:

```bash
docker compose up --build
```

### 2. Scan WhatsApp QR Code

On first launch, the `bridge` container will print a QR code in the terminal logs:

```text
[Bridge] Scan QR code below with WhatsApp:
█████████████████████████████████
█████████████████████████████████
...
```

1. Open WhatsApp on your phone.
2. Go to **Settings** > **Linked Devices** > **Link a Device**.
3. Scan the QR code rendered in your terminal.
4. Once linked, you will see `[Bridge] WhatsApp connection successfully established!`.

*(Note: Login credentials are saved in the persistent Docker volume `baileys_auth`, so subsequent restarts will not require scanning the QR code.)*

### 3. Discover Your WhatsApp Group ID

1. Send any test message (e.g. `hello`) in the target WhatsApp group with your phone.
2. Observe the `bridge` logs in your terminal:

```text
[Bridge] Received message in chat [120363xxxxxxxxxxxx@g.us] from [351xxxxxxxxx@s.whatsapp.net]: "hello"
[Bridge] NOTICE: TARGET_GROUP_ID is not set in environment. Group ID for this message is: 120363xxxxxxxxxxxx@g.us
```

3. Copy the group ID (ends with `@g.us`).

### 4. Configure `TARGET_GROUP_ID`

Create a `.env` file from `.env.example`:

```bash
cp .env.example .env
```

Edit `.env` and set your group ID:

```env
TARGET_GROUP_ID=120363xxxxxxxxxxxx@g.us
```

Restart the containers to apply the configuration:

```bash
docker compose up -d
```

---

## Verifying the Ping-Pong Loop

1. In your designated WhatsApp group, send the message:
   ```text
   ping
   ```
2. Check the `brain` container logs (`docker compose logs -f brain`):
   ```text
   [Brain] Received message in group 120363xxxxxxxxxxxx@g.us from 351xxxxxxxxx@s.whatsapp.net: "ping"
   [Brain] Sending reply 'pong' to group [120363xxxxxxxxxxxx@g.us] via http://bridge:3000/send
   ```
3. Look at your WhatsApp group — a `pong` reply will appear within a few seconds!
4. Send any other message (e.g., `Hello assistant`). It will be logged in `brain`, but no reply will be sent.

---

## Architecture Overview

```
┌─────────────────────┐       HTTP POST        ┌───────────────────┐
│   WhatsApp Group    │ <────────────────────> │   Baileys Bridge  │
└─────────────────────┘   Baileys Protocol     └─────────┬─────────┘
                                                         │
                                               HTTP POST │ HTTP POST
                                           /send │ /webhook/whatsapp
                                                         ▼
                                               ┌───────────────────┐
                                               │   Elixir Brain    │
                                               │ (Phoenix / Plug)  │
                                               └───────────────────┘
```
