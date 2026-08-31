<script setup>
import { computed, ref } from 'vue';

import Editor from 'dashboard/components-next/Editor/Editor.vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import InstructionSectionNavigator from './InstructionSectionNavigator.vue';

const props = defineProps({
  modelValue: { type: Object, required: true },
  descriptors: { type: Array, required: true },
  profileFields: { type: Array, required: true },
  profileOptions: { type: Object, required: true },
  compiledInstructions: { type: String, required: true },
  contentLength: { type: Number, required: true },
  maxLength: { type: Number, default: 50000 },
  editorKeyPrefix: { type: String, required: true },
  countLabel: { type: String, required: true },
  emptyPreviewLabel: { type: String, required: true },
  selectorLabel: { type: String, required: true },
  disabled: { type: Boolean, default: false },
  navigatorClass: { type: String, default: '' },
  navigatorVisibilityClass: { type: [String, Array], default: '' },
  contentVisibilityClass: { type: [String, Array], default: '' },
});

const emit = defineEmits(['update:modelValue']);
const { formatMessage } = useMessageFormatter();
const selectedSection = ref(
  props.descriptors.find(descriptor => descriptor.type === 'profile')?.key ||
    props.descriptors[0]?.key
);

const selectedItem = computed(() =>
  props.descriptors.find(item => item.key === selectedSection.value)
);
const formattedInstructions = computed(() =>
  formatMessage(props.compiledInstructions, false, false, false)
);
const isOverLimit = computed(() => props.contentLength > props.maxLength);
const editorOptions = [
  'strong',
  'em',
  'link',
  'bulletList',
  'orderedList',
  'undo',
  'redo',
];

const updateDocument = changes => {
  emit('update:modelValue', { ...props.modelValue, ...changes });
};

const updateProfile = (key, value) => {
  updateDocument({
    profile: { ...props.modelValue.profile, [key]: value },
    ...(key === 'language' && ['tr', 'en'].includes(value)
      ? { locale: value }
      : {}),
  });
};

const updateSection = value => {
  updateDocument({
    sections: {
      ...props.modelValue.sections,
      [selectedSection.value]: value,
    },
  });
};

defineExpose({ selectedSection, isOverLimit });
</script>

<template>
  <InstructionSectionNavigator
    :items="descriptors"
    :selected-key="selectedSection"
    :class="[navigatorClass, navigatorVisibilityClass]"
    @select="selectedSection = $event"
  />

  <section
    class="min-w-0 flex-col"
    :class="[
      contentVisibilityClass,
      selectedItem.type === 'preview'
        ? 'min-h-[44rem]'
        : 'min-h-[44rem] md:h-[calc(100dvh-15rem)] md:min-h-[36rem] md:max-h-[64rem] md:overflow-hidden',
    ]"
  >
    <label class="mb-4 flex flex-col gap-1 text-sm font-medium md:hidden">
      {{ selectorLabel }}
      <select
        v-model="selectedSection"
        class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal"
      >
        <option v-for="item in descriptors" :key="item.key" :value="item.key">
          {{ item.shortTitle }}
        </option>
      </select>
    </label>

    <header class="flex-shrink-0 border-b border-n-weak pb-4">
      <h2 class="m-0 text-xl font-semibold text-n-slate-12">
        {{ selectedItem.title }}
      </h2>
      <p class="mb-0 mt-1 max-w-2xl text-sm text-n-slate-11">
        {{ selectedItem.description }}
      </p>
    </header>

    <div
      v-if="selectedItem.type === 'preview'"
      data-testid="all-instructions-content"
      class="py-5 pr-1"
    >
      <div
        v-if="compiledInstructions"
        v-dompurify-html="formattedInstructions"
        class="prose prose-sm max-w-none break-words text-n-slate-12 dark:prose-invert prose-headings:scroll-mt-4 prose-headings:text-n-slate-12 prose-h2:mb-2 prose-h2:mt-6 prose-h2:border-b prose-h2:border-n-weak prose-h2:pb-2 prose-p:leading-relaxed prose-li:leading-relaxed"
      />
      <div v-else class="py-12 text-center text-sm text-n-slate-10">
        {{ emptyPreviewLabel }}
      </div>
    </div>

    <div
      v-else-if="selectedItem.type === 'profile'"
      class="min-h-0 flex-1 overflow-y-auto py-5 pr-1"
    >
      <div class="grid grid-cols-1 gap-5 sm:grid-cols-2">
        <label
          v-for="field in profileFields"
          :key="field.key"
          class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
        >
          {{ field.label }}
          <select
            :value="modelValue.profile[field.key]"
            :disabled="disabled"
            class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal"
            @change="updateProfile(field.key, $event.target.value)"
          >
            <option
              v-for="option in profileOptions[field.key]"
              :key="option[0]"
              :value="option[0]"
            >
              {{ option[1] }}
            </option>
          </select>
        </label>
      </div>
    </div>

    <div
      v-else
      data-testid="instruction-section-content"
      class="min-h-0 flex-1 overflow-y-auto py-5 pr-1"
    >
      <Editor
        :key="selectedSection"
        class="[&_.ProseMirror]:text-[0.9375rem] [&_.ProseMirror]:leading-6 [&_.ProseMirror_li]:!text-[0.9375rem] [&_.ProseMirror_li]:!leading-6 [&_.ProseMirror_p]:!text-[0.9375rem] [&_.ProseMirror_p]:!leading-6"
        :model-value="modelValue.sections[selectedSection] || ''"
        :editor-key="`${editorKeyPrefix}-${selectedSection}`"
        :aria-label="selectedItem.title"
        :placeholder="selectedItem.placeholder"
        :disabled="disabled"
        :max-length="maxLength"
        :show-character-count="false"
        :enable-canned-responses="false"
        variant="article"
        :enabled-menu-options="editorOptions"
        min-height="10rem"
        max-height="clamp(10rem, calc(100dvh - 37rem), 28rem)"
        @update:model-value="updateSection"
      />
      <slot name="section-footer" :section="selectedSection" />
    </div>

    <p
      class="m-0 flex-shrink-0 border-t border-n-weak pt-3 text-right text-xs"
      :class="isOverLimit ? 'text-n-ruby-11' : 'text-n-slate-10'"
    >
      {{ countLabel }}
    </p>
  </section>
</template>
