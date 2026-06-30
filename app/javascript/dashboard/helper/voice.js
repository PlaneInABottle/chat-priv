import { CONTENT_TYPES } from 'dashboard/components-next/message/constants';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import { useCallsStore } from 'dashboard/stores/calls';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import types from 'dashboard/store/mutation-types';

export const TERMINAL_STATUSES = [
  'completed',
  'busy',
  'failed',
  'no-answer',
  'canceled',
  'missed',
  'ended',
];

export const isInbound = direction => direction === 'inbound';

const isVoiceCallMessage = message => {
  return CONTENT_TYPES.VOICE_CALL === message?.content_type;
};

const isTruthy = value => value === true || value === 'true';
const isLivekit = provider => provider === VOICE_CALL_PROVIDERS.LIVEKIT;
const isTerminalStatus = status => TERMINAL_STATUSES.includes(status);

const shouldSkipCall = (callDirection, senderId, currentUserId) => {
  return callDirection === 'outbound' && senderId !== currentUserId;
};

const extractAssigneeId = conversation => {
  return conversation?.assignee_id || conversation?.meta?.assignee?.id || null;
};

const isAssignedToAnotherAgent = (assigneeId, currentUserId) => {
  if (currentUserId == null) return false;
  return !!assigneeId && assigneeId !== currentUserId;
};

const shouldShowCall = ({
  callDirection,
  senderId,
  assigneeId,
  currentUserId,
}) => {
  if (shouldSkipCall(callDirection, senderId, currentUserId)) return false;
  // Outbound calls are scoped to the initiator via shouldSkipCall; the
  // conversation may be auto-assigned to a different agent on creation, so
  // skip the assignee filter for outbound to avoid hiding the caller's own widget.
  if (callDirection === 'outbound') return true;
  return !isAssignedToAnotherAgent(assigneeId, currentUserId);
};

// Offline/busy agents shouldn't get a ringing popup for inbound calls, but
// outbound calls always belong to the initiator regardless of their status,
// and existing (already-surfaced) calls keep going so a status change
// mid-call doesn't yank away an active widget.
const shouldRingInbound = (callDirection, currentUserAvailability) => {
  if (callDirection === 'outbound') return true;
  return currentUserAvailability === 'online';
};

const shouldNotifyHumanForLivekit = ({ provider, handoffStatus }) => {
  if (!isLivekit(provider)) return true;
  return ['requested', 'accepted'].includes(handoffStatus);
};

function extractCallerSnapshot(message) {
  // Snapshot caller info from the message at add-time so the widget can keep
  // rendering it after the user navigates away from a conversation list that
  // had the conversation hydrated (and Vuex evicts it from the store).
  // Only incoming messages carry the contact as the sender; on outbound calls
  // the sender is the initiating agent, so skip the snapshot and let the widget
  // fall back to the conversation's contact (conversation.meta.sender).
  if (message?.message_type !== MESSAGE_TYPE.INCOMING) return null;
  const sender = message?.sender;
  if (!sender) return null;
  return {
    name: sender.name,
    phone: sender.phone_number,
    avatar: sender.avatar || sender.thumbnail,
    additionalAttributes: sender.additional_attributes || {},
  };
}

function extractCallData(message) {
  const call = message?.call || {};
  const data = message?.content_attributes?.data || {};
  return {
    callSid: call.provider_call_id || data.call_sid,
    callId: call.id || data.call_id,
    provider: call.provider || data.call_source,
    status: call.status || data.status,
    startedAt: call.started_at || data.started_at || message?.created_at,
    callDirection:
      call.direction === 'outgoing'
        ? 'outbound'
        : data.call_direction || 'inbound',
    conversationId: message?.conversation_id,
    inboxId: message?.inbox_id ?? message?.conversation?.inbox_id,
    assigneeId: extractAssigneeId(message?.conversation),
    senderId: message?.sender?.id,
    caller: extractCallerSnapshot(message),
    testCall: isTruthy(call.test_call ?? data.test_call),
    handoffStatus: call.handoff_status || data.handoff_status,
    aiStatus: call.ai_status || data.ai_status,
  };
}

export function handleVoiceCallCreated(
  message,
  currentUserId,
  currentUserAvailability
) {
  if (!isVoiceCallMessage(message)) return;

  const {
    callSid,
    callId,
    provider,
    callDirection,
    conversationId,
    inboxId,
    assigneeId,
    senderId,
    testCall,
    handoffStatus,
    startedAt,
  } = extractCallData(message);

  if (testCall) return;
  if (!shouldNotifyHumanForLivekit({ provider, handoffStatus })) return;

  if (
    !shouldShowCall({
      callDirection,
      senderId,
      assigneeId,
      currentUserId,
    })
  ) {
    return;
  }

  if (!shouldRingInbound(callDirection, currentUserAvailability)) return;

  const callsStore = useCallsStore();
  callsStore.addCall({
    callSid,
    callId,
    provider,
    startedAt,
    conversationId,
    inboxId,
    callDirection,
    senderId,
    caller: extractCallerSnapshot(message),
  });
}

export function handleVoiceCallUpdated(
  commit,
  message,
  currentUserId,
  currentUserAvailability
) {
  if (!isVoiceCallMessage(message)) return;

  const {
    callSid,
    callId,
    provider,
    status,
    callDirection,
    conversationId,
    inboxId,
    assigneeId,
    senderId,
    testCall,
    handoffStatus,
    startedAt,
  } = extractCallData(message);

  const callsStore = useCallsStore();

  callsStore.handleCallStatusChanged({ callSid, status, conversationId });

  commit(types.UPDATE_MESSAGE_CALL_STATUS, {
    conversationId,
    callStatus: status,
    callSid,
  });

  if (testCall) {
    callsStore.removeCall(callSid);
    return;
  }

  if (
    !shouldShowCall({
      callDirection,
      senderId,
      assigneeId,
      currentUserId,
    })
  ) {
    callsStore.removeCall(callSid);
    return;
  }

  if (!shouldNotifyHumanForLivekit({ provider, handoffStatus })) {
    callsStore.removeCall(callSid);
    return;
  }

  if (status === 'ringing') {
    if (!shouldRingInbound(callDirection, currentUserAvailability)) return;

    callsStore.addCall({
      callSid,
      callId,
      provider,
      startedAt,
      conversationId,
      inboxId,
      callDirection,
      senderId,
      caller: extractCallerSnapshot(message),
    });
  }
}

export function handleVoiceCallStatusPayload(
  data,
  currentUserId,
  currentUserAvailability
) {
  const callSid =
    data?.provider_call_id || data?.call_sid || data?.livekit_room_name;
  if (!callSid) return;

  const callsStore = useCallsStore();
  callsStore.handleCallStatusChanged({
    callSid,
    status: data?.status,
    conversationId: data?.conversation_id,
  });

  if (isTerminalStatus(data?.status) || isTruthy(data?.test_call)) {
    callsStore.removeCall(callSid);
    return;
  }

  if (!isLivekit(data?.provider)) return;

  if (
    !shouldNotifyHumanForLivekit({
      provider: data.provider,
      handoffStatus: data.handoff_status,
    })
  ) {
    callsStore.removeCall(callSid);
    return;
  }

  const callDirection =
    data?.direction === 'outgoing'
      ? 'outbound'
      : data?.call_direction || data?.direction || 'inbound';

  if (
    !shouldRingInbound(callDirection, currentUserAvailability) ||
    !shouldShowCall({
      callDirection,
      senderId: data?.sender_id,
      assigneeId: data?.assignee_id,
      currentUserId,
    })
  ) {
    return;
  }

  callsStore.addCall({
    callSid,
    callId: data?.id || data?.call_id,
    provider: data.provider,
    startedAt: data?.started_at,
    conversationId: data?.conversation_id,
    inboxId: data?.inbox_id,
    callDirection,
    senderId: data?.sender_id,
    caller: data?.caller,
  });
}

export function syncConversationCallVisibility(conversation, currentUserId) {
  const assigneeId = extractAssigneeId(conversation);
  if (!isAssignedToAnotherAgent(assigneeId, currentUserId)) return;

  // Outbound calls belong to the initiator regardless of who the conversation
  // is currently assigned to (auto-assignment may flip mid-call). Mirror
  // shouldShowCall's outbound exception so an in-progress outbound call isn't
  // ripped out from under the caller when the conversation reassigns.
  const callsStore = useCallsStore();
  const callsToRemove = callsStore.calls.filter(
    call =>
      call.conversationId === conversation.id &&
      !shouldShowCall({
        callDirection: call.callDirection,
        senderId: call.senderId,
        assigneeId,
        currentUserId,
      })
  );
  callsToRemove.forEach(call => callsStore.removeCall(call.callSid));
}
