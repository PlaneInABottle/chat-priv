<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, watch } from 'vue';
import Message from './Message.vue';
import VoiceTranscriptSegment from './VoiceTranscriptSegment.vue';
import VoiceToolEventSegment from './VoiceToolEventSegment.vue';
import {
  CONTENT_TYPES,
  MESSAGE_TYPES,
  VOICE_CALL_STATUS,
} from './constants.js';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useMapGetter } from 'dashboard/composables/store.js';
import MessageApi from 'dashboard/api/inbox/message.js';
import VoiceAPI from 'dashboard/api/voice.js';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

/**
 * Props definition for the component
 * @typedef {Object} Props
 * @property {Array} readMessages - Array of read messages
 * @property {Array} unReadMessages - Array of unread messages
 * @property {Number} currentUserId - ID of the current user
 * @property {Boolean} isAnEmailChannel - Whether this is an email channel
 * @property {Object} inboxSupportsReplyTo - Inbox reply support configuration
 * @property {Array} messages - Array of all messages [These are not in camelcase]
 */
const props = defineProps({
  currentUserId: {
    type: Number,
    required: true,
  },
  firstUnreadId: {
    type: Number,
    default: null,
  },
  isAnEmailChannel: {
    type: Boolean,
    default: false,
  },
  inboxSupportsReplyTo: {
    type: Object,
    default: () => ({ incoming: false, outgoing: false }),
  },
  messages: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['retry', 'voiceTranscriptUpdated']);

const allMessages = computed(() => {
  return useCamelCase(props.messages, {
    deep: true,
    stopPaths: ['content_attributes.translations'],
  });
});

const currentChat = useMapGetter('getSelectedChat');

// Cache for fetched reply messages to avoid duplicate API calls
const fetchedReplyMessages = reactive(new Map());
const callDetailsById = reactive({});
const fetchingCallIds = reactive({});

const TERMINAL_VOICE_CALL_STATUSES = [
  VOICE_CALL_STATUS.COMPLETED,
  VOICE_CALL_STATUS.NO_ANSWER,
  VOICE_CALL_STATUS.FAILED,
  VOICE_CALL_STATUS.BUSY,
  VOICE_CALL_STATUS.CANCELED,
  VOICE_CALL_STATUS.MISSED,
  VOICE_CALL_STATUS.ENDED,
];

const mergeUniqueById = (existingItems = [], incomingItems = []) => {
  const byId = new Map();
  [...existingItems, ...incomingItems].forEach(item => {
    if (item?.id) byId.set(item.id, item);
  });
  return Array.from(byId.values());
};

const mergeCallDetails = (existing = {}, incoming = {}) => ({
  ...existing,
  ...incoming,
  transcriptSegments: mergeUniqueById(
    existing.transcriptSegments,
    incoming.transcriptSegments
  ),
  toolEventSummaries: mergeUniqueById(
    existing.toolEventSummaries,
    incoming.toolEventSummaries
  ),
});

const getCallId = message =>
  message?.call?.id ||
  message?.contentAttributes?.data?.callId ||
  message?.contentAttributes?.data?.call_id;

const isVoiceCallMessage = message =>
  message?.contentType === CONTENT_TYPES.VOICE_CALL && getCallId(message);

const hasVoiceCallForCallId = callId =>
  allMessages.value.some(
    message => Number(getCallId(message)) === Number(callId)
  );

const ensureCallDetails = async message => {
  if (!isVoiceCallMessage(message)) return;

  const callId = getCallId(message);
  if (callDetailsById[callId] || fetchingCallIds[callId]) return;

  fetchingCallIds[callId] = true;
  try {
    const response = await VoiceAPI.getCall(callId);
    callDetailsById[callId] = mergeCallDetails(
      callDetailsById[callId],
      useCamelCase(response.data, { deep: true })
    );
    if (callDetailsById[callId]?.transcriptSegments?.length) {
      emit('voiceTranscriptUpdated');
    }
  } catch {
    // Keep the normal voice-call message visible when call details cannot load.
  } finally {
    delete fetchingCallIds[callId];
  }
};

const transcriptSegmentsForMessage = message => {
  const callId = getCallId(message);
  return callDetailsById[callId]?.transcriptSegments || [];
};

const callDetailsForMessage = message =>
  callDetailsById[getCallId(message)] || {};

const messageWithCallDetails = message => {
  if (!isVoiceCallMessage(message)) return message;

  const details = callDetailsForMessage(message);
  if (!Object.keys(details).length) return message;

  return {
    ...message,
    call: {
      ...(message.call || {}),
      ...details,
    },
  };
};

const voiceAgentNameForMessage = message =>
  callDetailsForMessage(message).voiceAgentName || '';

const toolEventSummariesForMessage = message =>
  callDetailsForMessage(message).toolEventSummaries || [];

const isTerminalVoiceCallMessage = message => {
  const details = callDetailsForMessage(message);
  const status =
    details.status ||
    message?.call?.status ||
    message?.contentAttributes?.data?.status;
  return TERMINAL_VOICE_CALL_STATUSES.includes(status);
};

const callTimelineRowsForMessage = message => {
  const voiceAgentName = voiceAgentNameForMessage(message);
  const transcriptItems = transcriptSegmentsForMessage(message).map(
    segment => ({
      type: 'voice_transcript',
      id: `voice-transcript-${segment.id}`,
      segment,
      voiceAgentName,
      sortAt: segment.createdAt || segment.created_at,
    })
  );
  const toolItems = toolEventSummariesForMessage(message).map(event => ({
    type: 'voice_tool_event',
    id: `voice-tool-event-${event.id}`,
    event,
    voiceAgentName,
    sortAt: event.createdAt || event.created_at,
  }));

  return [...transcriptItems, ...toolItems].sort(
    (a, b) => new Date(a.sortAt || 0) - new Date(b.sortAt || 0)
  );
};

const timelineItems = computed(() =>
  allMessages.value.flatMap((message, messageIndex) => {
    const messageItem = {
      type: 'message',
      id: `message-${message.id}`,
      message,
      messageIndex,
    };
    const callTimelineRows = callTimelineRowsForMessage(message);
    if (callTimelineRows.length && isTerminalVoiceCallMessage(message)) {
      return [...callTimelineRows, messageItem];
    }
    return [messageItem, ...callTimelineRows];
  })
);

const onTranscriptSegment = data => {
  const callId = data.call_id || data.callId;
  if (!callId || !hasVoiceCallForCallId(callId)) return;

  const existing = callDetailsById[callId] || { transcriptSegments: [] };
  const segment = useCamelCase(data.segment, { deep: true });
  const segments = existing.transcriptSegments || [];
  if (segments.some(item => item.id === segment.id)) return;

  callDetailsById[callId] = mergeCallDetails(existing, {
    transcriptSegments: [...segments, segment],
  });
  emit('voiceTranscriptUpdated');
};

const onStatusChanged = data => {
  const callId = data.id || data.call_id || data.callId;
  if (!callId || !hasVoiceCallForCallId(callId)) return;

  callDetailsById[callId] = mergeCallDetails(
    callDetailsById[callId],
    useCamelCase(data, { deep: true })
  );
};

const onToolEvent = data => {
  const callId = data.call_id || data.callId;
  if (!callId || !hasVoiceCallForCallId(callId)) return;

  const existing = callDetailsById[callId] || { toolEventSummaries: [] };
  const event = useCamelCase(data.event, { deep: true });
  const events = existing.toolEventSummaries || [];
  if (events.some(item => item.id === event.id)) return;

  callDetailsById[callId] = mergeCallDetails(existing, {
    toolEventSummaries: [...events, event],
  });
  emit('voiceTranscriptUpdated');
};

const refreshVisibleVoiceCalls = () => {
  const visibleCallIds = new Set(
    allMessages.value
      .filter(isVoiceCallMessage)
      .map(message => getCallId(message))
  );
  Object.keys(callDetailsById).forEach(callId => {
    if (!visibleCallIds.has(Number(callId)) && !visibleCallIds.has(callId)) {
      delete callDetailsById[callId];
    }
  });

  allMessages.value.forEach(ensureCallDetails);
};

watch(allMessages, refreshVisibleVoiceCalls, { immediate: true });
watch(() => currentChat.value?.id, refreshVisibleVoiceCalls);

onMounted(() => {
  emitter.on('voice.transcript_segment', onTranscriptSegment);
  emitter.on('voice.status_changed', onStatusChanged);
  emitter.on('voice.tool_event', onToolEvent);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, refreshVisibleVoiceCalls);
});

onBeforeUnmount(() => {
  emitter.off('voice.transcript_segment', onTranscriptSegment);
  emitter.off('voice.status_changed', onStatusChanged);
  emitter.off('voice.tool_event', onToolEvent);
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, refreshVisibleVoiceCalls);
});

/**
 * Fetches a specific message from the API by trying to get messages around it
 * @param {number} messageId - The ID of the message to fetch
 * @param {number} conversationId - The ID of the conversation
 * @returns {Promise<Object|null>} - The fetched message or null if not found/error
 */
const fetchReplyMessage = async (messageId, conversationId) => {
  // Return cached result if already fetched
  if (fetchedReplyMessages.has(messageId)) {
    return fetchedReplyMessages.get(messageId);
  }

  try {
    const response = await MessageApi.getPreviousMessages({
      conversationId,
      before: messageId + 100,
      after: messageId - 100,
    });

    const messages = response.data?.payload || [];
    const targetMessage = messages.find(msg => msg.id === messageId);

    if (targetMessage) {
      const camelCaseMessage = useCamelCase(targetMessage);
      fetchedReplyMessages.set(messageId, camelCaseMessage);
      return camelCaseMessage;
    }

    // Cache null result to avoid repeated API calls
    fetchedReplyMessages.set(messageId, null);
    return null;
  } catch (error) {
    fetchedReplyMessages.set(messageId, null);
    return null;
  }
};

/**
 * Determines if a message should be grouped with the next message
 * @param {Number} index - Index of the current message
 * @param {Array} searchList - Array of messages to check
 * @returns {Boolean} - Whether the message should be grouped with next
 */
const shouldGroupWithNext = (index, searchList) => {
  if (index === searchList.length - 1) return false;

  const current = searchList[index];
  const next = searchList[index + 1];

  if (next.status === 'failed') return false;

  const nextSenderId = next.senderId ?? next.sender?.id;
  const currentSenderId = current.senderId ?? current.sender?.id;
  const hasSameSender = nextSenderId === currentSenderId;

  const nextMessageType = next.messageType;
  const currentMessageType = current.messageType;

  const areBothTemplates =
    nextMessageType === MESSAGE_TYPES.TEMPLATE &&
    currentMessageType === MESSAGE_TYPES.TEMPLATE;

  if (!hasSameSender || areBothTemplates) return false;

  if (currentMessageType !== nextMessageType) return false;

  // Check if messages are in the same minute by rounding down to nearest minute
  return Math.floor(next.createdAt / 60) === Math.floor(current.createdAt / 60);
};

/**
 * Gets the message that was replied to
 * @param {Object} parentMessage - The message containing the reply reference
 * @returns {Object|null} - The message being replied to, or null if not found
 */
const getInReplyToMessage = parentMessage => {
  if (!parentMessage) return null;

  const inReplyToMessageId =
    parentMessage.contentAttributes?.inReplyTo ??
    parentMessage.content_attributes?.in_reply_to;

  if (!inReplyToMessageId) return null;

  // Try to find in current messages first
  let replyMessage = props.messages?.find(msg => msg.id === inReplyToMessageId);

  // Then try store messages
  if (!replyMessage && currentChat.value?.messages) {
    replyMessage = currentChat.value.messages.find(
      msg => msg.id === inReplyToMessageId
    );
  }

  // Then check fetch cache
  if (!replyMessage && fetchedReplyMessages.has(inReplyToMessageId)) {
    replyMessage = fetchedReplyMessages.get(inReplyToMessageId);
  }

  // If still not found and we have conversation context, fetch it
  if (!replyMessage && currentChat.value?.id) {
    fetchReplyMessage(inReplyToMessageId, currentChat.value.id);
    return null; // Let UI handle loading state
  }

  return replyMessage ? useCamelCase(replyMessage) : null;
};
</script>

<template>
  <ul class="px-4 bg-n-surface-1">
    <slot name="beforeAll" />
    <template v-for="item in timelineItems" :key="item.id">
      <slot
        v-if="
          item.type === 'message' &&
          firstUnreadId &&
          item.message.id === firstUnreadId
        "
        name="unreadBadge"
      />
      <Message
        v-if="item.type === 'message'"
        v-bind="messageWithCallDetails(item.message)"
        :is-email-inbox="isAnEmailChannel"
        :in-reply-to="getInReplyToMessage(item.message)"
        :group-with-next="shouldGroupWithNext(item.messageIndex, allMessages)"
        :inbox-supports-reply-to="inboxSupportsReplyTo"
        :current-user-id="currentUserId"
        data-clarity-mask="True"
        @retry="emit('retry', item.message)"
      />
      <VoiceTranscriptSegment
        v-else-if="item.type === 'voice_transcript'"
        :segment="item.segment"
        :voice-agent-name="item.voiceAgentName"
        data-clarity-mask="True"
      />
      <VoiceToolEventSegment
        v-else
        :event="item.event"
        :voice-agent-name="item.voiceAgentName"
        data-clarity-mask="True"
      />
    </template>
    <slot name="after" />
  </ul>
</template>
