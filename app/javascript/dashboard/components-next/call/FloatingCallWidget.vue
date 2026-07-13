<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useCallSession } from 'dashboard/composables/useCallSession';
import { useVoiceSession } from 'dashboard/composables/useVoiceSession';
import { setWhatsappCallMuted } from 'dashboard/composables/useWhatsappCallSession';
import VoiceAPI from 'dashboard/api/voice';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import WindowVisibilityHelper from 'dashboard/helper/AudioAlerts/WindowVisibilityHelper';
import CallCard from 'dashboard/components-next/call/CallCard.vue';
import countriesList from 'shared/constants/countries.js';
import { useCallsStore } from 'dashboard/stores/calls';

const RINGTONE_URL = '/audio/dashboard/bell.mp3';

const route = useRoute();
const router = useRouter();
const store = useStore();
const callsStore = useCallsStore();

const {
  activeCall,
  incomingCalls,
  hasActiveCall,
  isJoining,
  joinCall,
  endCall: endCallSession,
  rejectIncomingCall,
  dismissCall,
  formattedCallDuration,
} = useCallSession();

// Browser-side mute is available for WhatsApp and Kozmopath Voice. Twilio calls are
// mediated server-side and don't expose a mic track here.
const isMuted = ref(false);
const isKozmopathVoiceCall = call =>
  call?.provider === VOICE_CALL_PROVIDERS.KOZMOPATH_VOICE;

const primaryIncomingCall = computed(() =>
  hasActiveCall.value ? null : incomingCalls.value[0] || null
);

const voiceSessionCall = computed(() => {
  let call = null;
  if (activeCall.value?.provider === VOICE_CALL_PROVIDERS.KOZMOPATH_VOICE) {
    call = activeCall.value;
  } else if (
    primaryIncomingCall.value?.provider === VOICE_CALL_PROVIDERS.KOZMOPATH_VOICE
  ) {
    call = primaryIncomingCall.value;
  }
  if (!call?.callId) return null;
  return { id: call.callId };
});
const {
  remoteAudioRef: voiceRemoteAudioRef,
  sessionError: voiceSessionError,
  isJoining: isJoiningKozmopathVoice,
  isMuted: isKozmopathVoiceMuted,
  isConnected: isKozmopathVoiceConnected,
  joinRoom: joinKozmopathVoiceRoom,
  disconnectRoom: disconnectKozmopathVoiceRoom,
  toggleMute: toggleKozmopathVoiceMute,
} = useVoiceSession({ call: voiceSessionCall });
const isCallAccepting = call =>
  isKozmopathVoiceCall(call) ? isJoiningKozmopathVoice.value : isJoining.value;
const voiceJoinedCallReference = ref(null);
const navigateToConversationAfterKozmopathVoiceJoin = ref(null);

const stackedIncomingCalls = computed(() =>
  hasActiveCall.value ? incomingCalls.value : incomingCalls.value.slice(1)
);

const mainCardState = computed(() => {
  if (hasActiveCall.value) return VOICE_CALL_DIRECTION.ONGOING;
  const direction = primaryIncomingCall.value?.callDirection;
  return direction === VOICE_CALL_DIRECTION.OUTBOUND
    ? VOICE_CALL_DIRECTION.OUTGOING
    : VOICE_CALL_DIRECTION.INCOMING;
});

// Stacked cards are always non-active (ringing) calls, so reflect each call's
// real direction. An outbound call must render as OUTGOING — otherwise it shows
// the incoming-only dismiss (✕) control and the agent could drop it locally
// without terminating, leaving the customer ringing with no widget to end it.
const stackedCardState = call =>
  call?.callDirection === VOICE_CALL_DIRECTION.OUTBOUND
    ? VOICE_CALL_DIRECTION.OUTGOING
    : VOICE_CALL_DIRECTION.INCOMING;

const isActiveKozmopathVoice = computed(() =>
  isKozmopathVoiceCall(activeCall.value)
);
const isActiveWhatsapp = computed(
  () => activeCall.value?.provider === VOICE_CALL_PROVIDERS.WHATSAPP
);
const showMute = computed(
  () => isActiveWhatsapp.value || isActiveKozmopathVoice.value
);
const activeMuted = computed(() =>
  isActiveKozmopathVoice.value ? isKozmopathVoiceMuted.value : isMuted.value
);

const toggleMute = () => {
  if (isActiveKozmopathVoice.value) {
    toggleKozmopathVoiceMute();
    return;
  }
  isMuted.value = !isMuted.value;
  setWhatsappCallMuted(isMuted.value);
};

watch(hasActiveCall, active => {
  if (!active) isMuted.value = false;
});

// Convert ISO 3166-1 alpha-2 country code (e.g. "US") to its regional indicator
// flag emoji. Returns empty string if the code is missing or malformed.
const countryCodeToFlag = code => {
  if (!code || code.length !== 2) return '';
  const base = 0x1f1e6;
  const offset = 'A'.charCodeAt(0);
  return String.fromCodePoint(
    ...code
      .toUpperCase()
      .split('')
      .map(c => base + (c.charCodeAt(0) - offset))
  );
};

const getCallInfo = call => {
  const conversation = store.getters.getConversationById(call?.conversationId);
  // Look up inbox from the call's own inboxId — the conversation can drop out
  // of the Vuex store when the user navigates between inbox views, so going
  // through `conversation.inbox_id` would lose the inbox name (and fall back
  // to the literal "Customer support" string).
  const inbox = store.getters['inboxes/getInbox'](call?.inboxId);
  const sender = conversation?.meta?.sender;
  // `caller` is the snapshot captured when the call first landed (from the
  // message sender or the WhatsApp cable payload). It outlives the
  // conversation being in the store, so prefer it for display.
  const caller = call?.caller;
  const additional =
    sender?.additional_attributes || caller?.additionalAttributes || {};
  const city = additional.city || '';
  const countryCode = additional.country_code || '';
  const country =
    additional.country ||
    countriesList.find(c => c.id === countryCode.toUpperCase())?.name ||
    '';
  // Prefer the richest available location string ("City, Country"); fall back to
  // whichever single field is present; finally fall back to the inbox name so
  // there's always something to show.
  const locationParts = [city, country].filter(Boolean);
  const location =
    locationParts.join(', ') || inbox?.name || 'Customer support';
  return {
    conversation,
    inbox,
    contactName:
      caller?.name ||
      sender?.name ||
      caller?.phone ||
      sender?.phone_number ||
      'Unknown caller',
    phoneNumber: caller?.phone || sender?.phone_number || '',
    inboxName: inbox?.name || 'Customer support',
    location,
    countryFlag: countryCodeToFlag(countryCode),
    hasLocation: locationParts.length > 0,
    avatar: caller?.avatar || sender?.avatar || sender?.thumbnail,
  };
};

const goToConversation = call => {
  const conversationId = call?.conversationId;
  const accountId = route.params.accountId;
  if (!conversationId || !accountId) return;
  router.push({
    path: frontendURL(conversationUrl({ accountId, id: conversationId })),
  });
};

const endKozmopathVoiceCall = async (call, reason) => {
  if (!call) return;

  try {
    if (call.callId) {
      await VoiceAPI.endCall(call.callId, { end_reason: reason });
    }
  } finally {
    disconnectKozmopathVoiceRoom();
    voiceJoinedCallReference.value = null;
    dismissCall(call.callSid);
  }
};

const handleEndCall = async () => {
  const call = activeCall.value;
  if (!call) return;

  if (isKozmopathVoiceCall(call)) {
    await endKozmopathVoiceCall(call, 'agent_ended_from_popup');
    return;
  }

  const inboxId = call.inboxId || getCallInfo(call).conversation?.inbox_id;
  if (!inboxId) return;

  await endCallSession({
    conversationId: call.conversationId,
    inboxId,
    callSid: call.callSid,
  });
};

const handleRejectCall = async call => {
  if (!call) return;

  if (isKozmopathVoiceCall(call)) {
    await endKozmopathVoiceCall(call, 'agent_rejected_from_popup');
    return;
  }

  await rejectIncomingCall(call.callSid);
};

const handleJoinKozmopathVoiceCall = async call => {
  if (hasActiveCall.value && activeCall.value?.callSid !== call.callSid) {
    await handleEndCall();
  }

  navigateToConversationAfterKozmopathVoiceJoin.value =
    call.conversationId || null;
  callsStore.setCallActive(call.callSid);
};

const handleJoinCall = async call => {
  if (!call || isJoining.value || isJoiningKozmopathVoice.value) return;

  if (isKozmopathVoiceCall(call)) {
    await handleJoinKozmopathVoiceCall(call);
    return;
  }

  const { conversation } = getCallInfo(call);

  if (hasActiveCall.value) {
    await handleEndCall();
  }

  // The conversation may not be hydrated yet (post-refresh seeding path);
  // call.inboxId already carries what joinCall needs.
  const result = await joinCall({
    conversationId: call.conversationId,
    inboxId: call.inboxId || conversation?.inbox_id,
    callSid: call.callSid,
  });

  if (result && conversation) {
    router.push({
      name: 'inbox_conversation',
      params: { conversation_id: call.conversationId },
    });
  }
};

// Auto-join outbound calls when window is visible. WhatsApp outbound has no
// separate join step (the offer was sent at initiate time and the answer is
// applied directly by the cable handler), so this only covers Twilio.
watch(
  () => incomingCalls.value[0],
  call => {
    if (
      call?.callDirection === VOICE_CALL_DIRECTION.OUTBOUND &&
      call?.provider !== VOICE_CALL_PROVIDERS.WHATSAPP &&
      !hasActiveCall.value &&
      WindowVisibilityHelper.isWindowVisible()
    ) {
      handleJoinCall(call);
    }
  },
  { immediate: true }
);

watch(
  () => activeCall.value?.callSid,
  async (callSid, previousCallSid) => {
    if (previousCallSid && previousCallSid === voiceJoinedCallReference.value) {
      disconnectKozmopathVoiceRoom();
      voiceJoinedCallReference.value = null;
    }

    const call = activeCall.value;
    if (!callSid || !isKozmopathVoiceCall(call)) return;
    if (
      isKozmopathVoiceConnected.value &&
      voiceJoinedCallReference.value === callSid
    ) {
      return;
    }

    const joined = await joinKozmopathVoiceRoom('agent');
    if (!joined) {
      callsStore.setCallInactive(callSid);
      navigateToConversationAfterKozmopathVoiceJoin.value = null;
      return;
    }

    voiceJoinedCallReference.value = callSid;
    if (
      navigateToConversationAfterKozmopathVoiceJoin.value &&
      call.conversationId ===
        navigateToConversationAfterKozmopathVoiceJoin.value
    ) {
      router.push({
        name: 'inbox_conversation',
        params: { conversation_id: call.conversationId },
      });
    }
    navigateToConversationAfterKozmopathVoiceJoin.value = null;
  },
  { immediate: true }
);

// Loop the ringtone while an inbound call is unanswered. Stop the moment any
// call is active (we joined), every inbound call cleared, or the widget tears
// down. The watcher only fires on the boolean transitioning, so additional
// ringing calls arriving while one is already ringing don't restart the audio
// — they silently stack into the UI without producing a fresh ring.
// Browser autoplay may reject the first play() if the tab has no prior
// user gesture; that's fine — the visual widget still surfaces the call.
const ringtone = new Audio(RINGTONE_URL);
ringtone.loop = true;
ringtone.volume = 1;

const stopRingtone = () => {
  ringtone.pause();
  ringtone.currentTime = 0;
};

const ringingInbound = computed(() =>
  incomingCalls.value.some(
    call => call.callDirection !== VOICE_CALL_DIRECTION.OUTBOUND
  )
);

watch(
  () => ringingInbound.value && !hasActiveCall.value,
  shouldRing => {
    if (shouldRing) {
      ringtone.play().catch(() => {});
    } else {
      stopRingtone();
    }
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  stopRingtone();
  disconnectKozmopathVoiceRoom();
});

const widgetAriaLabel = computed(() => {
  if (hasActiveCall.value) {
    const info = getCallInfo(activeCall.value);
    return `Active call with ${info.contactName}`;
  }
  const call = primaryIncomingCall.value;
  if (call) {
    const info = getCallInfo(call);
    return `Incoming call from ${info.contactName}`;
  }
  return 'Call widget';
});

const onEscape = () => {
  const call = primaryIncomingCall.value;
  if (call && !hasActiveCall.value) {
    handleRejectCall(call);
  } else if (hasActiveCall.value) {
    handleEndCall();
  }
};
</script>

<template>
  <div
    v-show="incomingCalls.length || hasActiveCall"
    role="dialog"
    aria-modal="true"
    :aria-label="widgetAriaLabel"
    class="fixed ltr:right-4 rtl:left-4 bottom-4 z-50 flex flex-col gap-3 max-w-[400px] w-[90vw] sm:w-[400px]"
    @keydown.escape="onEscape"
  >
    <div ref="voiceRemoteAudioRef" class="hidden" />

    <!-- Stacked incoming calls (shown above the primary card) -->
    <CallCard
      v-for="call in stackedIncomingCalls"
      :key="call.callSid"
      :call="call"
      :state="stackedCardState(call)"
      :call-info="getCallInfo(call)"
      :is-accepting="isCallAccepting(call)"
      @accept="handleJoinCall(call)"
      @reject="handleRejectCall(call)"
      @dismiss="dismissCall(call.callSid)"
      @go-to-conversation="goToConversation(call)"
    />

    <!-- Main Call Widget -->
    <CallCard
      v-if="hasActiveCall || primaryIncomingCall"
      :call="activeCall || primaryIncomingCall"
      :state="mainCardState"
      :call-info="getCallInfo(activeCall || primaryIncomingCall)"
      :duration="hasActiveCall ? formattedCallDuration : ''"
      :is-muted="activeMuted"
      :show-mute="hasActiveCall && showMute"
      :is-accepting="isCallAccepting(primaryIncomingCall)"
      @accept="handleJoinCall(primaryIncomingCall)"
      @reject="handleRejectCall(primaryIncomingCall)"
      @dismiss="dismissCall(primaryIncomingCall?.callSid)"
      @end="handleEndCall"
      @toggle-mute="toggleMute"
      @go-to-conversation="goToConversation(activeCall || primaryIncomingCall)"
    />
    <div
      v-if="voiceSessionError"
      class="mx-4 rounded-lg bg-n-ruby-3 px-3 py-2 text-sm text-n-ruby-11"
    >
      {{ voiceSessionError }}
    </div>
  </div>
</template>
