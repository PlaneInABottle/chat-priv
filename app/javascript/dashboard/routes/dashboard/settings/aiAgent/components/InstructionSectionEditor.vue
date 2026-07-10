<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';

const props = defineProps({
  section: { type: Object, required: true },
  title: { type: String, required: true },
  description: { type: String, default: '' },
  canMoveUp: { type: Boolean, default: false },
  canMoveDown: { type: Boolean, default: false },
});

const emit = defineEmits(['update', 'remove', 'moveUp', 'moveDown']);

const { t } = useI18n();
const isExpanded = ref(true);

const updateField = (field, value) => {
  emit('update', { ...props.section, [field]: value });
};

const editorOptions = [
  'strong',
  'em',
  'link',
  'bulletList',
  'orderedList',
  'undo',
  'redo',
];
</script>

<template>
  <section class="border-b border-n-weak py-5 first:border-t">
    <div class="flex min-w-0 items-start justify-between gap-3">
      <button
        type="button"
        class="flex min-w-0 flex-1 items-start gap-3 text-left"
        :aria-expanded="isExpanded"
        @click="isExpanded = !isExpanded"
      >
        <span
          class="mt-0.5 size-4 flex-shrink-0 text-n-slate-10"
          :class="
            isExpanded ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'
          "
        />
        <span class="min-w-0">
          <span class="block text-sm font-semibold text-n-slate-12">
            {{ title }}
          </span>
          <span v-if="description" class="mt-1 block text-sm text-n-slate-11">
            {{ description }}
          </span>
        </span>
      </button>

      <div class="flex flex-shrink-0 items-center gap-1">
        <Button
          v-if="canMoveUp"
          icon="i-lucide-arrow-up"
          size="sm"
          variant="ghost"
          color="slate"
          :aria-label="t('AI_ASSISTANT.INSTRUCTIONS.MOVE_UP')"
          @click="emit('moveUp')"
        />
        <Button
          v-if="canMoveDown"
          icon="i-lucide-arrow-down"
          size="sm"
          variant="ghost"
          color="slate"
          :aria-label="t('AI_ASSISTANT.INSTRUCTIONS.MOVE_DOWN')"
          @click="emit('moveDown')"
        />
        <Button
          v-if="section.custom"
          icon="i-lucide-trash-2"
          size="sm"
          variant="ghost"
          color="ruby"
          :aria-label="t('AI_ASSISTANT.INSTRUCTIONS.REMOVE_SECTION')"
          @click="emit('remove')"
        />
      </div>
    </div>

    <div v-if="isExpanded" class="ml-7 mt-4 flex flex-col gap-4">
      <label
        v-if="section.custom"
        class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
      >
        {{ t('AI_ASSISTANT.INSTRUCTIONS.SECTION_TITLE') }}
        <input
          :value="section.title"
          type="text"
          maxlength="80"
          class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal outline-none focus:border-n-brand"
          @input="updateField('title', $event.target.value)"
        />
      </label>

      <Editor
        :model-value="section.content"
        :editor-key="`instruction-${section.key}`"
        :placeholder="t('AI_ASSISTANT.INSTRUCTIONS.SECTION_PLACEHOLDER')"
        :max-length="50000"
        :show-character-count="false"
        :enable-canned-responses="false"
        variant="article"
        :enabled-menu-options="editorOptions"
        :min-height="8"
        :max-height="28"
        @update:model-value="updateField('content', $event)"
      />

      <label class="flex w-fit cursor-pointer items-center gap-2 text-sm">
        <input
          :checked="section.critical"
          type="checkbox"
          class="size-4 rounded border-n-strong text-n-brand"
          @change="updateField('critical', $event.target.checked)"
        />
        <span class="font-medium text-n-slate-12">
          {{ t('AI_ASSISTANT.INSTRUCTIONS.CRITICAL') }}
        </span>
        <span class="text-n-slate-10">
          {{ t('AI_ASSISTANT.INSTRUCTIONS.CRITICAL_HELP') }}
        </span>
      </label>

      <slot />
    </div>
  </section>
</template>
