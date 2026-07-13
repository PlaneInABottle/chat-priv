<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useAlert } from 'dashboard/composables';
import { useCallsStore } from 'dashboard/stores/calls';
import VoiceAPI from 'dashboard/api/voice';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  call: {
    type: Object,
    required: true,
  },
});

const TERMINAL_STATUSES = [
  'completed',
  'no-answer',
  'failed',
  'busy',
  'canceled',
  'missed',
  'ended',
];

const { t } = useI18n();
const callsStore = useCallsStore();
const latestCall = ref(null);
const isEnding = ref(false);

const source = computed(() => ({
  ...(props.call || {}),
  ...(latestCall.value || {}),
}));

const callField = (camelKey, snakeKey = camelKey) =>
  source.value?.[camelKey] ?? source.value?.[snakeKey];

const callId = computed(() => callField('id'));
const callSid = computed(
  () =>
    callField('callReference', 'call_reference') ||
    callField('roomName', 'room_name')
);
const status = computed(() => callField('status'));
const handoffStatus = computed(() =>
  callField('handoffStatus', 'handoff_status')
);
const aiStatus = computed(() => callField('aiStatus', 'ai_status'));
const isTerminal = computed(() => TERMINAL_STATUSES.includes(status.value));
const isActiveInCallWidget = computed(
  () =>
    callsStore.activeCall?.provider === VOICE_CALL_PROVIDERS.KOZMOPATH_VOICE &&
    callsStore.activeCall?.callSid === callSid.value
);

const statusText = computed(() => {
  if (handoffStatus.value === 'requested') {
    return t('CONVERSATION.VOICE_CALL.HANDOFF_REQUESTED');
  }
  if (handoffStatus.value === 'accepted') {
    return t('CONVERSATION.VOICE_CALL.HANDOFF_ACCEPTED');
  }
  if (aiStatus.value === 'silent') {
    return t('CONVERSATION.VOICE_CALL.AI_SILENT');
  }
  return t('CONVERSATION.VOICE_CALL.AI_ACTIVE');
});
const primaryActionLabel = computed(() =>
  handoffStatus.value === 'accepted' || aiStatus.value === 'silent'
    ? t('CONVERSATION.VOICE_CALL.JOIN_LIVE_CALL')
    : t('CONVERSATION.VOICE_CALL.TAKE_OVER')
);
const primaryActionIcon = computed(() =>
  handoffStatus.value === 'accepted' || aiStatus.value === 'silent'
    ? 'i-ph-headphones-bold'
    : 'i-ph-user-check-bold'
);

const refreshCall = async () => {
  if (!callId.value) return;

  try {
    const response = await VoiceAPI.getCall(callId.value);
    latestCall.value = useCamelCase(response.data, { deep: true });
  } catch {
    latestCall.value = null;
  }
};

const syncActiveCallStore = () => {
  if (!callSid.value || !callId.value) return;

  callsStore.addCall({
    callSid: callSid.value,
    callId: callId.value,
    provider: VOICE_CALL_PROVIDERS.KOZMOPATH_VOICE,
    startedAt: callField('startedAt', 'started_at'),
    conversationId: callField('conversationId', 'conversation_id'),
    inboxId: callField('inboxId', 'inbox_id'),
    callDirection: VOICE_CALL_DIRECTION.INBOUND,
  });
  callsStore.setCallActive(callSid.value);
};

const removeCallFromStore = () => {
  if (callSid.value) callsStore.removeCall(callSid.value);
};

const handleJoin = async () => {
  if (isActiveInCallWidget.value || isTerminal.value) return;

  await refreshCall();
  if (isTerminal.value) {
    removeCallFromStore();
    return;
  }

  syncActiveCallStore();
};

const handleEnd = async () => {
  if (!callId.value || isEnding.value || isTerminal.value) return;

  isEnding.value = true;
  try {
    const response = await VoiceAPI.endCall(callId.value, {
      end_reason: 'agent_ended',
    });
    latestCall.value = useCamelCase(response.data, { deep: true });
    removeCallFromStore();
    useAlert(t('VOICE_AI.SESSION.END_SUCCESS'));
  } catch {
    useAlert(t('VOICE_AI.SESSION.ACTION_ERROR'));
  } finally {
    isEnding.value = false;
  }
};

watch(() => props.call?.id, refreshCall, { immediate: true });
watch(isTerminal, terminal => {
  if (terminal) removeCallFromStore();
});
</script>

<template>
  <div
    v-show="!isTerminal"
    class="border-t border-n-weak bg-n-surface-1 px-4 py-2"
  >
    <div
      class="mx-auto flex w-full max-w-[56rem] flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex min-w-0 items-center gap-2">
        <span
          class="size-2 shrink-0 rounded-full bg-n-teal-9 ring-4 ring-n-teal-3"
        />
        <div class="min-w-0">
          <div class="truncate text-sm font-medium text-n-slate-12">
            {{ t('CONVERSATION.VOICE_CALL.CALL_IN_PROGRESS') }}
          </div>
          <div class="flex min-w-0 gap-1 text-xs text-n-slate-11">
            <span class="truncate">{{ statusText }}</span>
            <span v-if="isActiveInCallWidget" class="truncate text-n-slate-10">
              {{ t('CONVERSATION.VOICE_CALL.LIVE_SESSION') }}
            </span>
          </div>
        </div>
      </div>

      <div class="flex shrink-0 flex-wrap items-center gap-2">
        <NextButton
          v-if="!isActiveInCallWidget"
          type="button"
          size="sm"
          :label="primaryActionLabel"
          :icon="primaryActionIcon"
          teal
          :disabled="isEnding"
          @click="handleJoin"
        />
        <NextButton
          type="button"
          size="sm"
          :label="t('CONVERSATION.VOICE_CALL.END_CALL')"
          icon="i-ph-phone-x-bold"
          variant="outline"
          color="ruby"
          :disabled="isEnding"
          :is-loading="isEnding"
          @click="handleEnd"
        />
      </div>
    </div>
  </div>
</template>
