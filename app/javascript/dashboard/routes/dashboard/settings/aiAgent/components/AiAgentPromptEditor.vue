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

const promptMenuOptions = [
  'h1',
  'h2',
  'h3',
  'strong',
  'em',
  'strike',
  'link',
  'bulletList',
  'orderedList',
  'code',
  'undo',
  'redo',
];
</script>

<template>
  <Editor
    class="ai-agent-prompt-editor"
    editor-key="ai-agent-prompt-editor"
    :model-value="modelValue"
    :label="t('AI_AGENT.PROMPT.LABEL')"
    :placeholder="t('AI_AGENT.PROMPT.PLACEHOLDER')"
    :message="message"
    :message-type="messageType"
    :max-length="maxLength"
    variant="article"
    :enabled-menu-options="promptMenuOptions"
    :min-height="12"
    :max-height="48"
    show-character-count
    :enable-canned-responses="false"
    @update:model-value="emit('update:modelValue', $event)"
  />
</template>

<style lang="scss" scoped>
.ai-agent-prompt-editor {
  :deep(.ProseMirror.ProseMirror-woot-style) {
    p,
    li {
      @apply text-sm leading-6;
    }

    h1 {
      @apply text-xl font-normal leading-7;
    }

    h2 {
      @apply text-lg font-normal leading-7;
    }

    h3,
    h4,
    h5,
    h6 {
      @apply text-base font-normal leading-6;
    }
  }
}
</style>
