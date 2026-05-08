<script setup>
import { useI18n } from 'vue-i18n';
import Editor from 'dashboard/components-next/Editor/Editor.vue';

defineProps({
  modelValue: { type: String, default: '' },
  message: { type: String, default: '' },
  messageType: { type: String, default: 'info' },
  maxLength: { type: Number, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
</script>

<template>
  <Editor
    editor-key="ai-agent-prompt-editor"
    :model-value="modelValue"
    :label="t('AI_AGENT.PROMPT.LABEL')"
    :placeholder="t('AI_AGENT.PROMPT.PLACEHOLDER')"
    :message="message"
    :message-type="messageType"
    :max-length="maxLength"
    show-character-count
    :enable-canned-responses="false"
    @update:model-value="emit('update:modelValue', $event)"
  />
</template>
