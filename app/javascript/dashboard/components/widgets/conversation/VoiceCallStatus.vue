<script setup>
import { computed } from 'vue';
import {
  VOICE_CALL_STATUS,
  VOICE_CALL_DIRECTION,
  VOICE_CALL_END_REASON,
} from 'dashboard/components-next/message/constants';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  status: { type: String, default: '' },
  direction: { type: String, default: '' },
  endReason: { type: String, default: '' },
  messagePreviewClass: { type: [String, Array, Object], default: '' },
});

const LABEL_KEYS = {
  [VOICE_CALL_STATUS.IN_PROGRESS]: 'CONVERSATION.VOICE_CALL.CALL_IN_PROGRESS',
  [VOICE_CALL_STATUS.COMPLETED]: 'CONVERSATION.VOICE_CALL.CALL_ENDED',
  [VOICE_CALL_STATUS.ENDED]: 'CONVERSATION.VOICE_CALL.CALL_ENDED',
  [VOICE_CALL_STATUS.BUSY]: 'CONVERSATION.VOICE_CALL.BUSY',
  [VOICE_CALL_STATUS.CANCELED]: 'CONVERSATION.VOICE_CALL.CANCELED',
};

const ICON_MAP = {
  [VOICE_CALL_STATUS.IN_PROGRESS]: 'i-ph-phone-call',
  [VOICE_CALL_STATUS.NO_ANSWER]: 'i-ph-phone-x',
  [VOICE_CALL_STATUS.FAILED]: 'i-ph-phone-x',
  [VOICE_CALL_STATUS.REJECTED]: 'i-ph-phone-x',
  [VOICE_CALL_STATUS.BUSY]: 'i-ph-phone-x',
  [VOICE_CALL_STATUS.CANCELED]: 'i-ph-phone-slash',
  [VOICE_CALL_STATUS.MISSED]: 'i-ph-phone-x',
};

const COLOR_MAP = {
  [VOICE_CALL_STATUS.IN_PROGRESS]: 'text-n-teal-9',
  [VOICE_CALL_STATUS.RINGING]: 'text-n-teal-9',
  [VOICE_CALL_STATUS.COMPLETED]: 'text-n-slate-11',
  [VOICE_CALL_STATUS.ENDED]: 'text-n-slate-11',
  [VOICE_CALL_STATUS.NO_ANSWER]: 'text-n-ruby-9',
  [VOICE_CALL_STATUS.FAILED]: 'text-n-ruby-9',
  [VOICE_CALL_STATUS.REJECTED]: 'text-n-ruby-9',
  [VOICE_CALL_STATUS.BUSY]: 'text-n-ruby-9',
  [VOICE_CALL_STATUS.CANCELED]: 'text-n-slate-11',
  [VOICE_CALL_STATUS.MISSED]: 'text-n-ruby-9',
};

const isOutbound = computed(
  () => props.direction === VOICE_CALL_DIRECTION.OUTBOUND
);
const isFailed = computed(() =>
  [
    VOICE_CALL_STATUS.NO_ANSWER,
    VOICE_CALL_STATUS.FAILED,
    VOICE_CALL_STATUS.REJECTED,
    VOICE_CALL_STATUS.BUSY,
    VOICE_CALL_STATUS.MISSED,
  ].includes(props.status)
);
const wasDeclinedByAgent = computed(
  () =>
    isFailed.value &&
    !isOutbound.value &&
    props.endReason === VOICE_CALL_END_REASON.AGENT_REJECTED
);

const labelKey = computed(() => {
  if (LABEL_KEYS[props.status]) return LABEL_KEYS[props.status];
  if (props.status === VOICE_CALL_STATUS.RINGING) {
    return isOutbound.value
      ? 'CONVERSATION.VOICE_CALL.OUTGOING_CALL'
      : 'CONVERSATION.VOICE_CALL.INCOMING_CALL';
  }
  if (wasDeclinedByAgent.value) {
    return 'CONVERSATION.VOICE_CALL.MISSED_CALL_DECLINED_BY';
  }
  return isFailed.value
    ? 'CONVERSATION.VOICE_CALL.MISSED_CALL'
    : 'CONVERSATION.VOICE_CALL.INCOMING_CALL';
});

const iconName = computed(() => {
  if (wasDeclinedByAgent.value) return 'i-ph-phone-slash';
  if (ICON_MAP[props.status]) return ICON_MAP[props.status];
  return isOutbound.value ? 'i-ph-phone-outgoing' : 'i-ph-phone-incoming';
});

const statusColor = computed(() => {
  if (wasDeclinedByAgent.value) return 'text-n-amber-10';
  return COLOR_MAP[props.status] || 'text-n-slate-11';
});
</script>

<template>
  <div
    class="my-0 mx-2 leading-6 h-6 flex-1 min-w-0 text-sm overflow-hidden text-ellipsis whitespace-nowrap"
    :class="messagePreviewClass"
  >
    <Icon
      class="inline-block -mt-0.5 align-middle size-4"
      :icon="iconName"
      :class="statusColor"
    />
    <span class="mx-1" :class="statusColor">
      {{ $t(labelKey) }}
    </span>
  </div>
</template>
