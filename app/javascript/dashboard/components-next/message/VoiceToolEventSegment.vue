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

const description = computed(() => {
  const params = {
    agent: agentName.value,
    tool: props.event.tool,
  };

  switch (props.event.tool) {
    case 'ikas_catalog_search':
      return t('CONVERSATION.VOICE_CALL.TOOL_IKAS_CATALOG_SEARCH', params);
    case 'ikas_lookup_order':
      return t('CONVERSATION.VOICE_CALL.TOOL_IKAS_LOOKUP_ORDER', params);
    case 'human_handoff':
    case 'request_human_handoff':
      return t('CONVERSATION.VOICE_CALL.TOOL_HUMAN_HANDOFF', params);
    case 'end_customer_call':
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
  <li
    class="mb-2 flex w-full list-none justify-center"
    data-testid="voice-tool-event-segment"
  >
    <article
      class="max-w-lg rounded-full border border-n-amber-5 bg-n-amber-2 px-3 py-2 text-xs text-n-amber-12"
    >
      <div class="flex flex-wrap items-center justify-center gap-x-2 gap-y-1">
        <span class="font-medium">{{ description }}</span>
        <span class="text-n-amber-11">{{ statusLabel }}</span>
        <span v-if="formattedTime" class="tabular-nums text-n-amber-10">
          {{ formattedTime }}
        </span>
      </div>
      <p v-if="event.errorMessage" class="m-0 mt-1 text-center text-n-ruby-11">
        {{ event.errorMessage }}
      </p>
    </article>
  </li>
</template>
