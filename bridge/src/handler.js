import { ELIXIR_WEBHOOK_URL, WEBHOOK_SECRET } from "./config.js";
import { isBridgeSelfMessage } from "./loop-prevention.js";

// Phoenix's default 8 MB body limit — stay comfortably below it for base64 media.
export const MAX_MEDIA_BASE64 = 5_500_000; // ~4 MB original image

const WEBHOOK_MAX_RETRIES = 3;
const WEBHOOK_RETRY_DELAY_MS = 1_000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Headers for brain webhook POSTs. When a WEBHOOK_SECRET is configured the
 * brain requires it (see brain/lib/brain_web/router.ex verify_webhook_token).
 */
function webhookHeaders() {
  const headers = { "Content-Type": "application/json" };
  if (WEBHOOK_SECRET) {
    headers["x-webhook-token"] = WEBHOOK_SECRET;
  }
  return headers;
}

/**
 * POSTs a payload to the brain webhook with retries. Returns the response on
 * success, or null when every attempt fails.
 */
async function postToBrain(payload) {
  for (let attempt = 1; attempt <= WEBHOOK_MAX_RETRIES; attempt++) {
    try {
      const response = await fetch(ELIXIR_WEBHOOK_URL, {
        method: "POST",
        headers: webhookHeaders(),
        body: JSON.stringify(payload),
      });

      if (response.ok) {
        return response;
      }

      console.error(
        `[Bridge] Webhook returned HTTP ${response.status} (attempt ${attempt}/${WEBHOOK_MAX_RETRIES})`,
      );
    } catch (err) {
      console.error(
        `[Bridge] Failed to send webhook to Elixir brain (attempt ${attempt}/${WEBHOOK_MAX_RETRIES}):`,
        err.message,
      );
    }

    if (attempt < WEBHOOK_MAX_RETRIES) {
      await sleep(WEBHOOK_RETRY_DELAY_MS * attempt);
    }
  }

  return null;
}

/**
 * Sends a direct feedback message to a group, ignoring failures (best effort).
 */
async function sendGroupReply(client, groupId, text) {
  try {
    await client.sendMessage(groupId, text);
  } catch (err) {
    console.error("[Bridge] Failed to send feedback message:", err.message);
  }
}

/**
 * Handles every message_create event from WhatsApp.
 *
 * Flow:
 *   1. Drop empty messages.
 *   2. Drop messages identified as bot echoes (loop prevention).
 *   3. Resolve the real group JID; only group messages (@g.us) are forwarded.
 *   4. Forward the message payload to the Elixir brain (which decides, per
 *      group, whether to introduce itself, gate activation, or process commands).
 */
export async function handleIncomingMessage(client, message) {
  if (!message.body && !message.hasMedia) return;

  if (isBridgeSelfMessage(message)) {
    console.log("[Bridge] Discarding bot response message:", message.body);
    return;
  }

  const groupId = message.fromMe ? message.to : message.from;

  // Multi-group: the brain handles activation per group. Only forward
  // group chats (private 1:1 messages are not supported).
  if (!groupId || !groupId.endsWith("@g.us")) {
    return;
  }

  let mediaData = null;
  if (
    message.hasMedia &&
    (message.type === "image" || message.type === "document")
  ) {
    console.log(
      "[Bridge] Attempting media download for message:",
      message.id?.id,
    );

    try {
      const messageMedia = await message.downloadMedia();

      if (messageMedia && messageMedia.data) {
        if (messageMedia.data.length > MAX_MEDIA_BASE64) {
          console.warn(
            `[Bridge] Media too large (${messageMedia.data.length} base64 chars), skipping download for message:`,
            message.id?.id,
          );

          await sendGroupReply(
            client,
            groupId,
            "[BOT] 📷 A imagem é demasiado grande para processar (máx. ~4 MB). Envia uma foto mais pequena.",
          );
          return;
        }

        mediaData = {
          mimetype: messageMedia.mimetype,
          data: messageMedia.data, // already base64-encoded by whatsapp-web.js
          filename: messageMedia.filename || null,
        };
        console.log(
          `[Bridge] Downloaded media (${mediaData.mimetype}, ${mediaData.data.length} chars base64)`,
        );
      } else {
        console.log(
          "[Bridge] Media download returned no data for message:",
          message.id?.id,
        );
      }
    } catch (err) {
      console.error("[Bridge] Failed to download media:", err.message);
    }
  }

  console.log("[Bridge] Processing incoming command from group", {
    group: groupId,
    sender: message.author ?? message.from,
    fromMe: message.fromMe,
    text: message.body,
    hasMedia: !!mediaData,
  });

  const response = await postToBrain({
    group_id: groupId,
    sender: message.author ?? message.from,
    text: message.body || "",
    media: mediaData,
    from_me: message.fromMe,
    timestamp: message.timestamp,
  });

  if (!response) {
    await sendGroupReply(
      client,
      groupId,
      "[BOT] 😕 Não consegui processar a tua mensagem agora. Tenta novamente daqui a pouco.",
    );
  }
}

/**
 * Handles a group_join notification. When the bot itself was added to a
 * group, the brain is notified so it can introduce itself.
 *
 * @param {object} client - The whatsapp-web.js Client instance.
 * @param {object} notification - A GroupNotification object.
 */
export async function handleGroupJoin(client, notification) {
  const recipients = notification?.recipientIds || [];

  const botIsRecipient = recipients.some((id) =>
    [client.info?.wid?._serialized, client.info?.wid?.user].includes(id),
  );

  if (!botIsRecipient) {
    return;
  }

  const groupId = notification?.chatId;
  if (!groupId || !groupId.endsWith("@g.us")) {
    return;
  }

  console.log("[Bridge] Bot was added to group", groupId);

  try {
    const response = await fetch(ELIXIR_WEBHOOK_URL, {
      method: "POST",
      headers: webhookHeaders(),
      body: JSON.stringify({
        event: "group_join",
        group_id: groupId,
      }),
    });

    if (!response.ok) {
      console.error(
        `[Bridge] group_join webhook returned HTTP ${response.status}`,
      );
    }
  } catch (err) {
    console.error(
      "[Bridge] Failed to notify brain of group_join:",
      err.message,
    );
  }
}
