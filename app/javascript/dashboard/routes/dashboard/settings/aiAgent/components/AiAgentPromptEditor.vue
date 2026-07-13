<script setup>
import { useI18n } from 'vue-i18n';
defineProps({
  modelValue: { type: String, default: '' },
  message: { type: String, default: '' },
  messageType: { type: String, default: 'info' },
  maxLength: { type: Number, required: true },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
</script>

<template>
  <label class="flex flex-col gap-1">
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('AI_AGENT.PROMPT.LABEL') }}
    </span>
    <textarea
      :value="modelValue"
      rows="14"
      :maxlength="maxLength"
      :disabled="disabled"
      :placeholder="t('AI_AGENT.PROMPT.PLACEHOLDER')"
      class="min-h-72 resize-y rounded-lg border border-n-weak bg-n-alpha-1 p-3 font-mono text-sm leading-6 text-n-slate-12 outline-none focus:border-n-brand disabled:cursor-not-allowed disabled:bg-n-alpha-2"
      @input="emit('update:modelValue', $event.target.value)"
    />
    <span class="flex items-start justify-between gap-3 text-xs">
      <span
        :class="messageType === 'error' ? 'text-n-ruby-11' : 'text-n-slate-10'"
      >
        {{ message }}
      </span>
      <span class="flex-shrink-0 text-n-slate-10"
        >{{ modelValue.length }} / {{ maxLength }}</span
      >
    </span>
  </label>
</template>
