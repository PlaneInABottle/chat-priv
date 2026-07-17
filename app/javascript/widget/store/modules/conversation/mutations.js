import { MESSAGE_TYPE } from 'widget/helpers/constants';
import { findUndeliveredMessage } from './helpers';

const isActiveAiOptionPrompt = message => {
  const attributes = message.content_attributes || {};
  return (
    message.content_type === 'input_select' &&
    attributes.ai_agent?.selection?.version === 1 &&
    !attributes.submitted_values &&
    !attributes.selection_unavailable
  );
};

const markSupersededAiOptionPrompts = (messages, incomingMessage) => {
  Object.values(messages).forEach(message => {
    if (
      !isActiveAiOptionPrompt(message) ||
      Number(message.id) >= Number(incomingMessage.id)
    ) {
      return;
    }

    message.content_attributes = {
      ...message.content_attributes,
      selection_unavailable: true,
    };
  });
};

export const mutations = {
  clearConversations($state) {
    $state.conversations = {};
    $state.pendingCustomAttributes = {};
    $state.pendingLabels = [];
  },
  pushMessageToConversation($state, message) {
    const { id, status, message_type: type } = message;

    const messagesInbox = $state.conversations;
    const isMessageIncoming = type === MESSAGE_TYPE.INCOMING;
    const isTemporaryMessage = status === 'in_progress';

    if (!isMessageIncoming || isTemporaryMessage) {
      messagesInbox[id] = message;
      return;
    }

    markSupersededAiOptionPrompts(messagesInbox, message);

    const [messageInConversation] = findUndeliveredMessage(
      messagesInbox,
      message
    );
    if (!messageInConversation) {
      messagesInbox[id] = message;
    } else {
      // [VITE] instead of leaving undefined behind, we remove it completely
      // remove the temporary message and replace it with the new message
      // messagesInbox[messageInConversation.id] = undefined;
      delete messagesInbox[messageInConversation.id];
      messagesInbox[id] = message;
    }
  },

  updateAttachmentMessageStatus($state, { message, tempId }) {
    const { id } = message;
    const messagesInbox = $state.conversations;

    const messageInConversation = messagesInbox[tempId];

    if (messageInConversation) {
      // [VITE] instead of leaving undefined behind, we remove it completely
      // remove the temporary message and replace it with the new message
      // messagesInbox[tempId] = undefined;
      delete messagesInbox[tempId];
      messagesInbox[id] = { ...message };
    }
  },

  setConversationUIFlag($state, uiFlags) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...uiFlags,
    };
  },

  setConversationListLoading($state, status) {
    $state.uiFlags.isFetchingList = status;
  },

  setMessagesInConversation($state, payload) {
    if (!payload.length) {
      $state.uiFlags.allMessagesLoaded = true;
      return;
    }

    payload.forEach(message => {
      $state.conversations[message.id] = message;
    });
    payload
      .filter(message => message.message_type === MESSAGE_TYPE.INCOMING)
      .forEach(message =>
        markSupersededAiOptionPrompts($state.conversations, message)
      );
  },

  setMissingMessagesInConversation($state, payload) {
    $state.conversation = payload;
  },

  updateMessage($state, { id, content_attributes }) {
    $state.conversations[id] = {
      ...$state.conversations[id],
      content_attributes: {
        ...($state.conversations[id].content_attributes || {}),
        ...content_attributes,
      },
    };
  },

  updateMessageMeta($state, { id, meta }) {
    const message = $state.conversations[id];
    if (!message) return;

    const newMeta = message.meta ? { ...message.meta, ...meta } : { ...meta };
    message.meta = { ...newMeta };
  },

  deleteMessage($state, id) {
    delete $state.conversations[id];
    // [VITE] In Vue 3 proxy objects, we can't delete properties by setting them to undefined
    // Instead, we have to use the delete operator
    // $state.conversations[id] = undefined;
  },

  toggleAgentTypingStatus($state, { status }) {
    $state.uiFlags.isAgentTyping = status === 'on';
  },

  setMetaUserLastSeenAt($state, lastSeen) {
    $state.meta.userLastSeenAt = lastSeen;
  },

  setLastMessageId($state) {
    const { conversations } = $state;
    const lastMessage = Object.values(conversations).pop();
    if (!lastMessage) return;
    const { id } = lastMessage;
    $state.lastMessageId = id;
  },

  setPendingCustomAttributes($state, data) {
    $state.pendingCustomAttributes = {
      ...$state.pendingCustomAttributes,
      ...data,
    };
  },

  setPendingLabels($state, label) {
    if (!$state.pendingLabels.includes(label)) {
      $state.pendingLabels.push(label);
    }
  },

  removePendingCustomAttribute($state, key) {
    const { [key]: _, ...rest } = $state.pendingCustomAttributes;
    $state.pendingCustomAttributes = rest;
  },

  removePendingLabel($state, label) {
    $state.pendingLabels = $state.pendingLabels.filter(l => l !== label);
  },

  clearPendingConversationMetadata($state) {
    $state.pendingCustomAttributes = {};
    $state.pendingLabels = [];
  },
};
