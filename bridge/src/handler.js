import { ELIXIR_WEBHOOK_URL, TARGET_GROUP_ID } from "./config.js";
import { isBridgeSelfMessage } from "./loop-prevention.js";

/**
 * Handles every message_create event from WhatsApp.
 *
 * Flow:
 *   1. Drop empty messages.
 *   2. Drop messages identified as bot echoes (loop prevention).
 *   3. Resolve the real group JID.
 *   4. Drop messages that don't belong to the configured TARGET_GROUP_ID.
 *   5. Forward the message payload to the Elixir brain.
 */
export async function handleIncomingMessage(client, message) {
  if (!message.body && !message.hasMedia) return;

  if (isBridgeSelfMessage(message)) {
    console.log("[Bridge] Discarding bot response message:", message.body);
    return;
  }

  const groupId = message.fromMe ? message.to : message.from;

  // Defensive: if TARGET_GROUP_ID is somehow empty, accept all messages.
  if (TARGET_GROUP_ID && groupId !== TARGET_GROUP_ID) {
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

  console.log("[Bridge] Processing incoming command from phone/group", {
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
