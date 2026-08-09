import { ELIXIR_WEBHOOK_URL } from "./config.js";
import { isBridgeSelfMessage } from "./loop-prevention.js";

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
  if (message.hasMedia && (message.type === "image" || message.type === "document")) {
    console.log(
      "[Bridge] Attempting media download for message:",
      message.id?.id,
    );

    try {
      const messageMedia = await message.downloadMedia();

      if (messageMedia && messageMedia.data) {
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

  try {
    const response = await fetch(ELIXIR_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        group_id: groupId,
        sender: message.author ?? message.from,
        text: message.body || "",
        media: mediaData,
        from_me: message.fromMe,
        timestamp: message.timestamp,
      }),
    });

    if (!response.ok) {
      console.error(`[Bridge] Webhook returned HTTP ${response.status}`);
    }
  } catch (err) {
    console.error(
      "[Bridge] Failed to send webhook to Elixir brain:",
      err.message,
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
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        event: "group_join",
        group_id: groupId,
      }),
    });

    if (!response.ok) {
      console.error(`[Bridge] group_join webhook returned HTTP ${response.status}`);
    }
  } catch (err) {
    console.error("[Bridge] Failed to notify brain of group_join:", err.message);
  }
}
