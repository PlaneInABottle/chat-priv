<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useMessageContext } from '../provider.js';
import {
  VOICE_CALL_STATUS,
  VOICE_CALL_DIRECTION,
  VOICE_CALL_OUTBOUND_INIT_STATUS,
  VOICE_CALL_END_REASON,
  MESSAGE_TYPES,
  ATTACHMENT_TYPES,
} from '../constants';
import { useCallActions } from 'dashboard/composables/useCallSession';
import { useLivekitVoiceSession } from 'dashboard/composables/useLivekitVoiceSession';
import { useWhatsappCallSession } from 'dashboard/composables/useWhatsappCallSession';
import { useCallsStore } from 'dashboard/stores/calls';
import VoiceAPI from 'dashboard/api/voice';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { formatDuration } from 'shared/helpers/timeHelper';
import { useAlert } from 'dashboard/composables';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import BaseBubble from 'next/message/bubbles/Base.vue';
import AudioChip from 'next/message/chips/Audio.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const ICON_MAP = {
  [VOICE_CALL_STATUS.IN_PROGRESS]: 'i-ph-phone-call-bold',
  [VOICE_CALL_STATUS.COMPLETED]: 'i-ph-phone-bold',
  [VOICE_CALL_STATUS.NO_ANSWER]: 'i-ph-phone-x-bold',
  [VOICE_CALL_STATUS.FAILED]: 'i-ph-phone-x-bold',
  [VOICE_CALL_STATUS.REJECTED]: 'i-ph-phone-x-bold',
};

const { t } = useI18n();
const store = useStore();
const {
  call,
  attachments,
  contentAttributes,
  conversationId,
  currentUserId,
  inboxId,
  sender,
  messageType,
} = useMessageContext();
const {
  joinCall,
  endCall,
  dismissCall,
  activeCall,
  hasActiveCall,
  isJoining: isLegacyJoining,
} = useCallActions();
const whatsappCallSession = useWhatsappCallSession();
const callsStore = useCallsStore();
const livekitCallDetails = ref(null);
const isTakingOverLivekit = ref(false);
const isEndingLivekit = ref(false);
const contactsUiFlags = useMapGetter('contacts/getUIFlags');
const isInitiatingCall = computed(
  () => contactsUiFlags.value?.isInitiatingCall || false
);

const contentData = computed(() => contentAttributes?.value?.data || {});
const callField = (camelKey, snakeKey = camelKey) => {
  const source = livekitCallDetails.value || call.value || {};
  return (
    source[camelKey] ??
    source[snakeKey] ??
    contentData.value[camelKey] ??
    contentData.value[snakeKey]
  );
};

const status = computed(() => callField('status'));
// Server-side call records use `outgoing`/`incoming`, while the Pinia store
// and a few API hops normalise to `outbound`/`inbound`. Accept either so the
// bubble label matches the message orientation no matter the source.
const isOutbound = computed(() => {
  const dir = callField('direction');
  if (
    dir === VOICE_CALL_DIRECTION.OUTGOING ||
    dir === VOICE_CALL_DIRECTION.OUTBOUND
  )
    return true;
  if (
    dir === VOICE_CALL_DIRECTION.INCOMING ||
    dir === VOICE_CALL_DIRECTION.INBOUND
  )
    return false;
  // Fall back to the message orientation: agent-authored messages sit on the
  // right (outbound) and contact-authored ones on the left.
  return messageType.value === MESSAGE_TYPES.OUTGOING;
});
const isWhatsapp = computed(
  () => callField('provider') === VOICE_CALL_PROVIDERS.WHATSAPP
);
const isLivekit = computed(
  () => callField('provider') === VOICE_CALL_PROVIDERS.LIVEKIT
);
const isFailed = computed(() =>
  [
    VOICE_CALL_STATUS.NO_ANSWER,
    VOICE_CALL_STATUS.FAILED,
    VOICE_CALL_STATUS.REJECTED,
  ].includes(status.value)
);
const isMissedInbound = computed(() => isFailed.value && !isOutbound.value);
const endReason = computed(() => callField('endReason', 'end_reason'));
const wasDeclinedByAgent = computed(
  () =>
    isMissedInbound.value &&
    endReason.value === VOICE_CALL_END_REASON.AGENT_REJECTED
);
const acceptedByAgentId = computed(() =>
  callField('acceptedByAgentId', 'accepted_by_agent_id')
);
const acceptedByAgentName = computed(() =>
  callField('acceptedByAgentName', 'accepted_by_agent_name')
);
const handoffStatus = computed(() =>
  callField('handoffStatus', 'handoff_status')
);
const aiStatus = computed(() => callField('aiStatus', 'ai_status'));
const conversationAssignee = computed(() => {
  const conversation = store.getters.getConversationById?.(
    conversationId?.value
  );
  return conversation?.meta?.assignee || null;
});
const displayAgentName = computed(() => {
  if (acceptedByAgentName.value) return acceptedByAgentName.value;
  if (acceptedByAgentId.value) {
    const agent = store.getters['agents/getAgentById'](acceptedByAgentId.value);
    if (agent?.available_name) return agent.available_name;
    if (agent?.name) return agent.name;
  }
  return conversationAssignee.value?.name || null;
});

const audioAttachment = computed(() =>
  (attachments?.value || []).find(a => a.fileType === ATTACHMENT_TYPES.AUDIO)
);

const durationSeconds = computed(() => {
  const fromCall = callField('durationSeconds', 'duration_seconds');
  if (fromCall != null) return fromCall;
  return (
    contentData.value?.durationSeconds || contentData.value?.duration_seconds
  );
});

const formattedDuration = computed(() => formatDuration(durationSeconds.value));

// Agent who handled the call (initiator on outbound, answerer on inbound), taken
// strictly from the persisted accept fields — never the conversation's current
// assignee, which would mis-attribute a historical call after a reassignment.
const handlerName = computed(() => {
  if (acceptedByAgentName.value) return acceptedByAgentName.value;
  if (!acceptedByAgentId.value) return null;
  const agent = store.getters['agents/getAgentById'](acceptedByAgentId.value);
  return agent?.available_name || agent?.name || null;
});

const handledBy = computed(() =>
  handlerName.value
    ? t('CONVERSATION.VOICE_CALL.HANDLED_BY', { agentName: handlerName.value })
    : null
);

const label = computed(() => {
  if (status.value === VOICE_CALL_STATUS.IN_PROGRESS) {
    return t('CONVERSATION.VOICE_CALL.CALL_IN_PROGRESS');
  }
  if (status.value === VOICE_CALL_STATUS.COMPLETED) {
    return t('CONVERSATION.VOICE_CALL.CALL_ENDED');
  }
  if (isFailed.value) {
    return isOutbound.value
      ? t('CONVERSATION.VOICE_CALL.NO_ANSWER_OUTBOUND_LABEL')
      : t('CONVERSATION.VOICE_CALL.MISSED_CALL');
  }
  // RINGING or an as-yet-unknown/initial status: orient purely by direction so an
  // outbound call never falls through to the "Incoming call" label.
  return isOutbound.value
    ? t('CONVERSATION.VOICE_CALL.OUTGOING_CALL')
    : t('CONVERSATION.VOICE_CALL.INCOMING_CALL');
});

const subtext = computed(() => {
  // Completed: "Handled by {agent} · 0:42" (drops either part when absent).
  if (status.value === VOICE_CALL_STATUS.COMPLETED) {
    return [handledBy.value, formattedDuration.value]
      .filter(Boolean)
      .join(' · ');
  }
  if (status.value === VOICE_CALL_STATUS.IN_PROGRESS) {
    if (isLivekit.value && handoffStatus.value === 'requested') {
      return t('CONVERSATION.VOICE_CALL.HANDOFF_REQUESTED');
    }
    if (isLivekit.value && handoffStatus.value === 'accepted') {
      return handledBy.value || t('CONVERSATION.VOICE_CALL.HANDOFF_ACCEPTED');
    }
    if (isLivekit.value && aiStatus.value === 'silent') {
      return t('CONVERSATION.VOICE_CALL.AI_SILENT');
    }
    if (isLivekit.value) {
      return t('CONVERSATION.VOICE_CALL.AI_ACTIVE');
    }
    return handledBy.value;
  }
  if (isFailed.value) {
    // Missed/failed calls have no handler, so keep the reason rather than "Handled by".
    if (isOutbound.value) {
      return t('CONVERSATION.VOICE_CALL.NO_ANSWER_OUTBOUND_SUBTEXT');
    }
    if (wasDeclinedByAgent.value && displayAgentName.value) {
      return t('CONVERSATION.VOICE_CALL.MISSED_CALL_DECLINED_BY', {
        agentName: displayAgentName.value,
      });
    }
    return t('CONVERSATION.VOICE_CALL.MISSED_CALL_INBOUND_SUBTEXT');
  }
  // RINGING or an as-yet-unknown/initial status.
  if (isOutbound.value) {
    return handledBy.value || t('CONVERSATION.VOICE_CALL.CALLING');
  }
  return t('CONVERSATION.VOICE_CALL.NOT_ANSWERED_YET');
});

const iconName = computed(() => {
  if (ICON_MAP[status.value]) return ICON_MAP[status.value];
  return isOutbound.value
    ? 'i-ph-phone-outgoing-bold'
    : 'i-ph-phone-incoming-bold';
});

// Subtle icon container — matches the design's tonal swatch over the bubble bg.
// Status drives the accent: teal for live, ruby for missed, neutral otherwise.
const iconContainerClass = computed(() => {
  if (status.value === VOICE_CALL_STATUS.IN_PROGRESS) {
    return 'bg-n-teal-3 text-n-teal-11';
  }
  if (status.value === VOICE_CALL_STATUS.RINGING) {
    return 'bg-n-teal-3 text-n-teal-11';
  }
  if (isMissedInbound.value) {
    return 'bg-n-alpha-2 text-n-ruby-9';
  }
  return 'bg-n-alpha-2 text-n-slate-12';
});

const callSid = computed(
  () =>
    callField('providerCallId', 'provider_call_id') ||
    contentData.value?.call_sid
);
const livekitCallId = computed(
  () => callField('id') || contentData.value?.call_id
);
const livekitCallForSession = computed(() => {
  if (!livekitCallId.value) return null;
  return { id: livekitCallId.value };
});
const {
  remoteAudioRef,
  sessionStatus: livekitSessionStatus,
  sessionError: livekitSessionError,
  activeParticipantType: livekitParticipantType,
  isJoining: isJoiningLivekit,
  isMuted: isLivekitMuted,
  isConnected: isLivekitConnected,
  joinRoom: joinLivekitRoom,
  disconnectRoom: disconnectLivekitRoom,
  toggleMute: toggleLivekitMute,
} = useLivekitVoiceSession({ call: livekitCallForSession });

const isLivekitTerminal = computed(() =>
  [
    VOICE_CALL_STATUS.COMPLETED,
    VOICE_CALL_STATUS.NO_ANSWER,
    VOICE_CALL_STATUS.FAILED,
  ].includes(status.value)
);
const canUseLivekitControls = computed(
  () =>
    isLivekit.value && Boolean(livekitCallId.value) && !isLivekitTerminal.value
);
const isLivekitActiveInCallWidget = computed(
  () =>
    activeCall.value?.provider === VOICE_CALL_PROVIDERS.LIVEKIT &&
    activeCall.value?.callSid === callSid.value
);
const displayLivekitSessionStatus = computed(() =>
  isLivekitActiveInCallWidget.value ? 'connected' : livekitSessionStatus.value
);

const canJoinCall = computed(() => {
  if (status.value !== VOICE_CALL_STATUS.RINGING) return false;
  if (isLivekit.value) return false;
  if (isOutbound.value) return false;
  if (acceptedByAgentId.value) return false;
  if (!callSid.value || !inboxId.value || !conversationId.value) return false;
  if (hasActiveCall.value && activeCall.value?.callSid === callSid.value)
    return false;
  const assignee = conversationAssignee.value;
  if (assignee?.id && assignee.id !== currentUserId.value) return false;
  return true;
});

const recordingAttachment = computed(() => {
  if (audioAttachment.value) return audioAttachment.value;
  const recording = callField('recording') || {};
  const url = callField('recordingUrl', 'recording_url');
  if (!url) return null;
  const contentType = recording.contentType || recording.content_type;
  return {
    dataUrl: url,
    fileType: ATTACHMENT_TYPES.AUDIO,
    extension: contentType === 'audio/ogg' ? 'ogg' : 'wav',
    transcribedText: callField('transcript') || '',
  };
});

const recordingStatus = computed(() => {
  const recording = callField('recording') || {};
  return recording.status || null;
});

const recordingStatusLabel = computed(() => {
  if (recordingAttachment.value) return '';
  if (['starting', 'active'].includes(recordingStatus.value)) {
    return t('CONVERSATION.VOICE_CALL.RECORDING_PROCESSING');
  }
  if (recordingStatus.value === 'failed') {
    return t('CONVERSATION.VOICE_CALL.RECORDING_FAILED');
  }
  return '';
});

const refreshLivekitCallDetails = async () => {
  if (!isLivekit.value || !livekitCallId.value) return;

  try {
    const response = await VoiceAPI.getCall(livekitCallId.value);
    livekitCallDetails.value = response.data;
  } catch {
    // Keep the historical message payload visible if the detail fetch fails.
  }
};

onMounted(() => {
  if (isLivekitTerminal.value) {
    refreshLivekitCallDetails();
  }
});

const handleJoinCall = async () => {
  if (!canJoinCall.value || isLegacyJoining.value) return;

  if (hasActiveCall.value && activeCall.value?.callSid !== callSid.value) {
    await endCall({
      conversationId: activeCall.value.conversationId,
      inboxId: activeCall.value.inboxId,
      callSid: activeCall.value.callSid,
    });
  }

  await joinCall({
    conversationId: conversationId.value,
    inboxId: inboxId.value,
    callSid: callSid.value,
  });
};

const canCallBack = computed(
  () =>
    isMissedInbound.value &&
    !isLivekit.value &&
    !!inboxId.value &&
    !!conversationId.value &&
    !hasActiveCall.value &&
    !callsStore.hasIncomingCall
);

const handleCallBack = async () => {
  if (!canCallBack.value || isInitiatingCall.value) return;
  try {
    if (isWhatsapp.value) {
      const response = await whatsappCallSession.initiateOutboundCall({
        conversationId: conversationId.value,
      });
      if (response?.status === VOICE_CALL_OUTBOUND_INIT_STATUS.LOCKED) return;
      // Permission template path returns no call id — show banner, no widget yet.
      if (!response?.id) {
        useAlert(
          response?.status ===
            VOICE_CALL_OUTBOUND_INIT_STATUS.PERMISSION_PENDING
            ? t('CONVERSATION.HEADER.WHATSAPP_CALL_PERMISSION_PENDING')
            : t('CONVERSATION.HEADER.WHATSAPP_CALL_PERMISSION_REQUESTED')
        );
        return;
      }
      callsStore.addCall({
        callSid: response.call_id,
        callId: response.id,
        conversationId: conversationId.value,
        inboxId: inboxId.value,
        callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
        provider: VOICE_CALL_PROVIDERS.WHATSAPP,
      });
      return;
    }
    const response = await store.dispatch('contacts/initiateCall', {
      contactId: sender.value?.id,
      inboxId: inboxId.value,
      conversationId: conversationId.value,
    });
    callsStore.addCall({
      callSid: response?.call_sid,
      conversationId: response?.conversation_id ?? conversationId.value,
      inboxId: inboxId.value,
      callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
    });
  } catch (error) {
    useAlert(error?.message || t('CONTACT_PANEL.CALL_FAILED'));
  }
};

const handleJoinLivekit = async () => {
  if (
    !canUseLivekitControls.value ||
    isLivekitConnected.value ||
    isLivekitActiveInCallWidget.value
  ) {
    return;
  }
  dismissCall(callSid.value);
  await joinLivekitRoom('agent');
};

const handleDisconnectLivekit = () => {
  if (isLivekitActiveInCallWidget.value) {
    dismissCall(callSid.value);
    return;
  }

  disconnectLivekitRoom();
};

const handleTakeOverLivekit = async () => {
  if (!canUseLivekitControls.value || isTakingOverLivekit.value) return;

  isTakingOverLivekit.value = true;
  try {
    const response = await VoiceAPI.takeOver(livekitCallId.value);
    livekitCallDetails.value = response.data;
    useAlert(t('VOICE_AI.SESSION.TAKE_OVER_SUCCESS'));
  } catch {
    useAlert(t('VOICE_AI.SESSION.ACTION_ERROR'));
  } finally {
    isTakingOverLivekit.value = false;
  }
};

const handleEndLivekit = async () => {
  if (!canUseLivekitControls.value || isEndingLivekit.value) return;

  isEndingLivekit.value = true;
  try {
    const response = await VoiceAPI.endCall(livekitCallId.value, {
      end_reason: 'agent_ended',
    });
    livekitCallDetails.value = response.data;
    disconnectLivekitRoom();
    dismissCall(callSid.value);
    useAlert(t('VOICE_AI.SESSION.END_SUCCESS'));
  } catch {
    useAlert(t('VOICE_AI.SESSION.ACTION_ERROR'));
  } finally {
    isEndingLivekit.value = false;
  }
};
</script>

<template>
  <BaseBubble class="!p-3 !max-w-md min-w-[240px]" hide-meta>
    <div class="flex flex-col gap-3 w-full">
      <!-- Header row: icon + title + duration/subtext -->
      <div class="flex gap-2.5 items-start">
        <div
          class="flex justify-center items-center rounded-xl size-11 shrink-0"
          :class="iconContainerClass"
        >
          <Icon class="size-4" :icon="iconName" />
        </div>
        <div class="flex flex-col flex-1 min-w-0 self-center">
          <span
            class="font-display text-sm font-medium leading-tight truncate tracking-tight"
          >
            {{ label }}
          </span>
          <span
            v-if="subtext"
            class="text-sm leading-tight truncate tracking-tight opacity-75"
          >
            {{ subtext }}
          </span>
        </div>
      </div>

      <!-- Audio player (when there's a recording) -->
      <div v-if="recordingAttachment" class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ $t('CONVERSATION.VOICE_CALL.REPLAY_RECORDING') }}
        </span>
        <AudioChip
          :attachment="recordingAttachment"
          show-transcribed-text
          :on-before-play="refreshLivekitCallDetails"
        />
      </div>
      <div
        v-else-if="recordingStatusLabel"
        class="rounded-lg bg-n-alpha-2 px-3 py-2 text-xs text-n-slate-11"
      >
        {{ recordingStatusLabel }}
      </div>

      <div v-if="isLivekit" ref="remoteAudioRef" class="hidden" />

      <div
        v-if="isLivekit && livekitSessionError"
        class="rounded-lg bg-n-ruby-3 px-3 py-2 text-sm text-n-ruby-11"
      >
        {{ livekitSessionError }}
      </div>

      <div
        v-if="canUseLivekitControls"
        class="rounded-lg bg-n-alpha-2 p-2 flex flex-col gap-2"
      >
        <div class="flex items-center justify-between gap-2 text-xs">
          <span class="font-medium text-n-slate-11">
            {{ $t('CONVERSATION.VOICE_CALL.LIVE_SESSION') }}
          </span>
          <span class="text-n-slate-10 capitalize">
            {{ displayLivekitSessionStatus }}
          </span>
        </div>

        <div class="grid grid-cols-2 gap-2">
          <NextButton
            v-if="!isLivekitConnected && !isLivekitActiveInCallWidget"
            type="button"
            :label="$t('CONVERSATION.VOICE_CALL.JOIN_LIVE_CALL')"
            icon="i-ph-headphones-bold"
            teal
            class="!rounded-full"
            :disabled="isJoiningLivekit"
            :is-loading="isJoiningLivekit && livekitParticipantType === 'agent'"
            @click="handleJoinLivekit"
          />
          <NextButton
            v-else
            type="button"
            :label="
              isLivekitMuted
                ? $t('CONVERSATION.VOICE_CALL.UNMUTE')
                : $t('CONVERSATION.VOICE_CALL.MUTE')
            "
            icon="i-ph-microphone-bold"
            variant="outline"
            color="slate"
            class="!rounded-full"
            @click="toggleLivekitMute"
          />
          <NextButton
            type="button"
            :label="$t('CONVERSATION.VOICE_CALL.TAKE_OVER')"
            icon="i-ph-user-check-bold"
            variant="outline"
            color="slate"
            class="!rounded-full"
            :disabled="handoffStatus === 'accepted'"
            :is-loading="isTakingOverLivekit"
            @click="handleTakeOverLivekit"
          />
          <NextButton
            v-if="isLivekitConnected || isLivekitActiveInCallWidget"
            type="button"
            :label="$t('CONVERSATION.VOICE_CALL.DISCONNECT')"
            icon="i-ph-phone-disconnect-bold"
            variant="outline"
            color="slate"
            class="!rounded-full"
            @click="handleDisconnectLivekit"
          />
          <NextButton
            type="button"
            :label="$t('CONVERSATION.VOICE_CALL.END_CALL')"
            icon="i-ph-phone-x-bold"
            variant="outline"
            color="ruby"
            class="!rounded-full"
            :is-loading="isEndingLivekit"
            @click="handleEndLivekit"
          />
        </div>
      </div>

      <!-- Call back button (missed inbound) -->
      <NextButton
        v-if="canCallBack"
        type="button"
        :label="$t('CONVERSATION.VOICE_CALL.CALL_BACK')"
        icon="i-ph-phone-bold"
        teal
        class="!rounded-full"
        :disabled="isInitiatingCall"
        @click="handleCallBack"
      />

      <!-- Join call button (ringing inbound) -->
      <NextButton
        v-if="canJoinCall"
        type="button"
        :label="$t('CONVERSATION.VOICE_CALL.JOIN_CALL')"
        icon="i-ph-phone-bold"
        teal
        class="!rounded-full"
        :disabled="isLegacyJoining"
        @click="handleJoinCall"
      />
    </div>
  </BaseBubble>
</template>
