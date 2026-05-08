<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import MessageFormatter from 'shared/helpers/MessageFormatter';

const props = defineProps({
  modelValue: { type: String, default: '' },
  message: { type: String, default: '' },
  messageType: { type: String, default: 'info' },
  maxLength: { type: Number, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const textareaRef = ref(null);
const showPreview = ref(false);

const previewHtml = computed(
  () => new MessageFormatter(props.modelValue).formattedMessage
);

const updateValue = value => {
  emit('update:modelValue', value);
};

const textareaElement = () => textareaRef.value?.$el?.querySelector('textarea');

const insertMarkdown = (before, after = '', placeholder = '') => {
  const textarea = textareaElement();
  const start = textarea?.selectionStart ?? props.modelValue.length;
  const end = textarea?.selectionEnd ?? props.modelValue.length;
  const selected = props.modelValue.slice(start, end) || placeholder;
  updateValue(
    `${props.modelValue.slice(0, start)}${before}${selected}${after}${props.modelValue.slice(end)}`
  );
};

const toolbarActions = [
  {
    key: 'bold',
    label: 'AI_AGENT.PROMPT.TOOLBAR.BOLD',
    before: '**',
    after: '**',
    placeholder: 'bold text',
  },
  {
    key: 'italic',
    label: 'AI_AGENT.PROMPT.TOOLBAR.ITALIC',
    before: '*',
    after: '*',
    placeholder: 'italic text',
  },
  {
    key: 'heading',
    label: 'AI_AGENT.PROMPT.TOOLBAR.HEADING',
    before: '## ',
    placeholder: 'Heading',
  },
  {
    key: 'bullets',
    label: 'AI_AGENT.PROMPT.TOOLBAR.BULLETS',
    before: '- ',
    placeholder: 'List item',
  },
  {
    key: 'numbered',
    label: 'AI_AGENT.PROMPT.TOOLBAR.NUMBERED',
    before: '1. ',
    placeholder: 'List item',
  },
  {
    key: 'section',
    label: 'AI_AGENT.PROMPT.TOOLBAR.SECTION',
    before: '\n---\n## ',
    placeholder: 'Section',
  },
];
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap gap-2">
      <button
        v-for="action in toolbarActions"
        :key="action.key"
        type="button"
        class="rounded border border-n-weak px-2 py-1 text-xs text-n-slate-12"
        @click="insertMarkdown(action.before, action.after, action.placeholder)"
      >
        {{ t(action.label) }}
      </button>
      <button
        type="button"
        class="rounded border border-n-weak px-2 py-1 text-xs text-n-slate-12"
        @click="showPreview = !showPreview"
      >
        {{
          showPreview
            ? t('AI_AGENT.PROMPT.PREVIEW.HIDE')
            : t('AI_AGENT.PROMPT.PREVIEW.SHOW')
        }}
      </button>
    </div>
    <TextArea
      ref="textareaRef"
      :model-value="modelValue"
      :label="t('AI_AGENT.PROMPT.LABEL')"
      :placeholder="t('AI_AGENT.PROMPT.PLACEHOLDER')"
      :message="message"
      :message-type="messageType"
      :max-length="maxLength"
      show-character-count
      auto-height
      min-height="8rem"
      max-height="20rem"
      resize
      @update:model-value="updateValue"
    />
    <div v-if="showPreview" class="rounded-lg border border-n-weak p-4">
      <h4 class="mb-2 text-sm font-medium text-n-slate-12">
        {{ t('AI_AGENT.PROMPT.PREVIEW.TITLE') }}
      </h4>
      <div v-dompurify-html="previewHtml" class="prose max-w-none text-sm" />
    </div>
  </div>
</template>
