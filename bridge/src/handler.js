import { ELIXIR_WEBHOOK_URL, WEBHOOK_SECRET } from "./config.js";
import { isBridgeSelfMessage } from "./loop-prevention.js";

export const MAX_MEDIA_BASE64 = 5_500_000;

const WEBHOOK_MAX_RETRIES = 3;
const WEBHOOK_RETRY_DELAY_MS = 1_000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function webhookHeaders() {
  const headers = { "Content-Type": "application/json" };
  if (WEBHOOK_SECRET) {
    headers["x-webhook-token"] = WEBHOOK_SECRET;
  }
  return headers;
}

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

async function getGroupName(client, msgOrNotif, groupId) {
  try {
    if (msgOrNotif && typeof msgOrNotif.getChat === "function") {
      const chat = await msgOrNotif.getChat();
      if (chat) {
        const name = chat.name || chat.formattedTitle || chat.subject;
        if (name) return name;
      }
    }
  } catch (err) {
    // Ignore error and try fallback
  }

  try {
    if (client && typeof client.getChatById === "function") {
      const chat = await client.getChatById(groupId);
      if (chat) {
        const name = chat.name || chat.formattedTitle || chat.subject;
        if (name) return name;
      }
    }
  } catch (err) {
    // Ignore error
  }

  return null;
}

/**
 * Handles every message_create event from WhatsApp.
 *
 * Drops empty messages, bot echoes, and non-group messages.
 * Forwards group messages to the Elixir brain webhook.
 */
export async function handleIncomingMessage(client, message) {
  if (!message.body && !message.hasMedia) return;

  if (isBridgeSelfMessage(message)) {
    console.log("[Bridge] Discarding bot response message:", message.body);
    return;
  }

  const groupId = message.fromMe ? message.to : message.from;

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
          return;
        }

        mediaData = {
          mimetype: messageMedia.mimetype,
          data: messageMedia.data,
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

  const groupName = await getGroupName(client, message, groupId);

  console.log("[Bridge] Processing incoming command from group", {
    group: groupId,
    groupName: groupName,
    sender: message.author ?? message.from,
    fromMe: message.fromMe,
    text: message.body,
    hasMedia: !!mediaData,
  });

  const response = await postToBrain({
    group_id: groupId,
    group_name: groupName,
    sender: message.author ?? message.from,
    text: message.body || "",
    media: mediaData,
    from_me: message.fromMe,
    timestamp: message.timestamp,
    message_id: message.id?.id,
  });

  if (!response) {
    console.error(
      "[Bridge] Webhook failed after all retries — no message sent to group",
    );
  }
}

/**
 * Handles group_join notification when bot is added to a group.
 * Notifies the brain so it can introduce itself.
 *
 * @param {object} client - whatsapp-web.js Client instance
 * @param {object} notification - GroupNotification object
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

  const groupName = await getGroupName(client, notification, groupId);

  console.log("[Bridge] Bot was added to group", groupId, groupName);

  try {
    const response = await fetch(ELIXIR_WEBHOOK_URL, {
      method: "POST",
      headers: webhookHeaders(),
      body: JSON.stringify({
        event: "group_join",
        group_id: groupId,
        group_name: groupName,
        message_id: `group_join_${groupId}_${Date.now()}`,
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
