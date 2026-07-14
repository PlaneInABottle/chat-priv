<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  event: {
    type: Object,
    required: true,
  },
  voiceAgentName: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();

const createdAt = computed(
  () => props.event.createdAt || props.event.created_at
);
const agentName = computed(
  () => props.voiceAgentName || t('CONVERSATION.VOICE_CALL.TRANSCRIPT_AI')
);

const statusLabel = computed(() => {
  if (props.event.status === 'error') {
    return t('CONVERSATION.VOICE_CALL.TOOL_ERROR');
  }
  if (props.event.status === 'rejected') {
    return t('CONVERSATION.VOICE_CALL.TOOL_REJECTED');
  }
  if (props.event.status === 'started') {
    return t('CONVERSATION.VOICE_CALL.TOOL_STARTED');
  }
  return t('CONVERSATION.VOICE_CALL.TOOL_EXECUTED');
});

const eventClass = computed(() => {
  if (props.event.status === 'error') {
    return 'border-n-ruby-5 bg-n-ruby-2 text-n-ruby-12';
  }
  if (props.event.status === 'rejected') {
    return 'border-n-slate-5 bg-n-alpha-2 text-n-slate-12';
  }
  if (props.event.status === 'started') {
    return 'border-n-amber-5 bg-n-amber-2 text-n-amber-12';
  }
  return 'border-n-teal-5 bg-n-teal-2 text-n-teal-12';
});

const mutedTextClass = computed(() => {
  if (props.event.status === 'error') return 'text-n-ruby-11';
  if (props.event.status === 'rejected') return 'text-n-slate-10';
  if (props.event.status === 'started') return 'text-n-amber-11';
  return 'text-n-teal-11';
});

const description = computed(() => {
  const params = {
    agent: agentName.value,
  };

  switch (props.event.action) {
    case 'catalog_search':
      return t('CONVERSATION.VOICE_CALL.TOOL_IKAS_CATALOG_SEARCH', params);
    case 'order_lookup':
      return t('CONVERSATION.VOICE_CALL.TOOL_IKAS_LOOKUP_ORDER', params);
    case 'human_handoff':
      return t('CONVERSATION.VOICE_CALL.TOOL_HUMAN_HANDOFF', params);
    case 'call_ended':
      return t('CONVERSATION.VOICE_CALL.TOOL_END_CUSTOMER_CALL', params);
    default:
      return t('CONVERSATION.VOICE_CALL.TOOL_USED', params);
  }
});

const formattedTime = computed(() => {
  if (!createdAt.value) return '';

  return new Intl.DateTimeFormat(undefined, {
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(createdAt.value));
});
</script>

<template>
  <article
    class="max-w-lg rounded-full border px-3 py-2 text-xs"
    :class="eventClass"
    data-testid="voice-tool-event-summary"
  >
    <div class="flex flex-wrap items-center justify-center gap-x-2 gap-y-1">
      <span class="font-medium">{{ description }}</span>
      <span :class="mutedTextClass">{{ statusLabel }}</span>
      <span v-if="formattedTime" class="tabular-nums" :class="mutedTextClass">
        {{ formattedTime }}
      </span>
    </div>
  </article>
</template>
