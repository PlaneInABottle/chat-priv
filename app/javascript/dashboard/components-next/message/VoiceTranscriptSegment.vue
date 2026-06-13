<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  segment: {
    type: Object,
    required: true,
  },
  voiceAgentName: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();

const role = computed(() => props.segment.role || 'caller');
const isCaller = computed(() => ['caller', 'customer'].includes(role.value));
const isAssistant = computed(() => ['ai', 'assistant'].includes(role.value));
const createdAt = computed(
  () => props.segment.createdAt || props.segment.created_at
);

const label = computed(() => {
  if (isCaller.value) return t('CONVERSATION.VOICE_CALL.TRANSCRIPT_CALLER');
  if (isAssistant.value) {
    return props.voiceAgentName || t('CONVERSATION.VOICE_CALL.TRANSCRIPT_AI');
  }
  return t('CONVERSATION.VOICE_CALL.TRANSCRIPT_AGENT');
});

const formattedTime = computed(() => {
  if (!createdAt.value) return '';

  return new Intl.DateTimeFormat(undefined, {
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(createdAt.value));
});

const alignmentClass = computed(() =>
  isCaller.value ? 'justify-start' : 'justify-end'
);

const bubbleClass = computed(() =>
  isCaller.value
    ? 'bg-n-alpha-2 border-n-weak text-n-slate-12 ltr:rounded-bl-sm rtl:rounded-br-sm'
    : 'bg-n-teal-2 border-n-teal-5 text-n-slate-12 ltr:rounded-br-sm rtl:rounded-bl-sm'
);
</script>

<template>
  <li
    class="mb-2 flex w-full list-none"
    :class="alignmentClass"
    aria-live="polite"
    aria-atomic="false"
    data-testid="voice-transcript-segment"
  >
    <article
      class="max-w-lg rounded-xl border px-3 py-2 text-sm shadow-none"
      :class="bubbleClass"
    >
      <header class="mb-1 flex items-center justify-between gap-3">
        <span
          class="text-xs font-medium uppercase tracking-wide text-n-slate-11"
        >
          {{ label }}
        </span>
        <span
          v-if="formattedTime"
          class="shrink-0 text-xs tabular-nums text-n-slate-10"
        >
          {{ formattedTime }}
        </span>
      </header>
      <p class="m-0 whitespace-pre-wrap leading-relaxed">
        {{ segment.text }}
      </p>
      <footer class="mt-1 text-[11px] leading-4 text-n-slate-10">
        {{ t('CONVERSATION.VOICE_CALL.MACHINE_TRANSCRIPT') }}
      </footer>
    </article>
  </li>
</template>
