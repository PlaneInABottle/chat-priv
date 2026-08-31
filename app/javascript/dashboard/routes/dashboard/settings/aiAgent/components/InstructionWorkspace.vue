<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import DraftTestPanel from './DraftTestPanel.vue';
import StructuredInstructionEditor from './StructuredInstructionEditor.vue';
import {
  INSTRUCTION_SECTION_KEYS,
  compileInstructionDocument,
  instructionContentLength,
} from '../helpers/instructionDocument';

const props = defineProps({
  modelValue: { type: Object, required: true },
  aiAgentId: { type: Number, required: true },
  isDirty: { type: Boolean, default: false },
  isDisabled: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue', 'configureHandoff', 'tested']);

const { t } = useI18n();
const mobileView = ref('edit');
const isTestFocused = ref(false);
const draftTestPanel = ref(null);

const profileOptions = computed(() => ({
  language: [
    ['not_set', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.NOT_SET')],
    [
      'same_as_customer',
      t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.LANGUAGE.SAME_AS_CUSTOMER'),
    ],
    ['tr', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.LANGUAGE.TURKISH')],
    ['en', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.LANGUAGE.ENGLISH')],
  ],
  tone: [
    ['not_set', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.NOT_SET')],
    ['natural', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TONE.NATURAL')],
    ['friendly', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TONE.FRIENDLY')],
    ['professional', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TONE.PROFESSIONAL')],
    ['concise', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TONE.CONCISE')],
  ],
  formality: [
    ['not_set', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.NOT_SET')],
    ['balanced', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.FORMALITY.BALANCED')],
    ['casual', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.FORMALITY.CASUAL')],
    ['formal', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.FORMALITY.FORMAL')],
  ],
  response_length: [
    ['not_set', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.NOT_SET')],
    [
      'balanced',
      t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.RESPONSE_LENGTH.BALANCED'),
    ],
    ['short', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.RESPONSE_LENGTH.SHORT')],
    [
      'detailed',
      t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.RESPONSE_LENGTH.DETAILED'),
    ],
  ],
}));

const profileFields = computed(() => [
  {
    key: 'language',
    label: t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.LANGUAGE_LABEL'),
  },
  { key: 'tone', label: t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TONE_LABEL') },
  {
    key: 'formality',
    label: t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.FORMALITY_LABEL'),
  },
  {
    key: 'response_length',
    label: t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.RESPONSE_LENGTH_LABEL'),
  },
]);

const sectionKeys = ['all', 'profile', ...INSTRUCTION_SECTION_KEYS];

const isProfileConfigured = computed(() =>
  Object.values(props.modelValue.profile).some(value => value !== 'not_set')
);

const isSectionConfigured = key => {
  if (key === 'all') return null;
  if (key === 'profile') return isProfileConfigured.value;
  return Boolean(props.modelValue.sections[key]?.trim());
};

const sectionStatusLabelKey = key => {
  if (key === 'all') return 'AI_ASSISTANT.INSTRUCTIONS.ALL_SECTIONS_STATUS';
  if (key === 'handoff' && !isSectionConfigured(key)) {
    return 'AI_ASSISTANT.INSTRUCTIONS.HANDOFF_DEFAULT_STATUS';
  }

  return isSectionConfigured(key)
    ? 'AI_ASSISTANT.INSTRUCTIONS.CONFIGURED'
    : 'AI_ASSISTANT.INSTRUCTIONS.NOT_CONFIGURED';
};

const sectionItems = computed(() =>
  sectionKeys.map(key => ({
    key,
    shortTitle: t(
      `AI_ASSISTANT.INSTRUCTIONS.SECTIONS.${key.toUpperCase()}.SHORT_TITLE`
    ),
    title: t(`AI_ASSISTANT.INSTRUCTIONS.SECTIONS.${key.toUpperCase()}.TITLE`),
    description: t(
      `AI_ASSISTANT.INSTRUCTIONS.SECTIONS.${key.toUpperCase()}.DESCRIPTION`
    ),
    icon: key === 'all' ? 'i-lucide-files' : '',
    configured: key === 'handoff' || isSectionConfigured(key),
    statusLabel: t(sectionStatusLabelKey(key)),
  }))
);

const totalLength = computed(() => instructionContentLength(props.modelValue));
const isOverLimit = computed(() => totalLength.value > 50000);
const compiledInstructions = computed(() =>
  compileInstructionDocument(props.modelValue)
);

defineExpose({
  refreshCredits: () => draftTestPanel.value?.refreshCredits?.(),
});

const descriptors = computed(() =>
  sectionItems.value.map(item => {
    let type = 'section';
    if (item.key === 'all') type = 'preview';
    if (item.key === 'profile') type = 'profile';

    return {
      ...item,
      type,
      placeholder:
        type === 'section'
          ? t(
              `AI_ASSISTANT.INSTRUCTIONS.SECTIONS.${item.key.toUpperCase()}.PLACEHOLDER`
            )
          : undefined,
    };
  })
);
</script>

<template>
  <div class="min-w-0">
    <div
      class="mb-5 grid grid-cols-2 rounded-lg bg-n-alpha-black2 p-1 min-[1360px]:hidden"
    >
      <button
        type="button"
        class="h-9 rounded-md text-sm font-medium hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :aria-pressed="mobileView === 'edit'"
        :class="
          mobileView === 'edit'
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11'
        "
        @click="mobileView = 'edit'"
      >
        {{ t('AI_ASSISTANT.INSTRUCTIONS.EDIT_VIEW') }}
      </button>
      <button
        type="button"
        class="h-9 rounded-md text-sm font-medium hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :aria-pressed="mobileView === 'test'"
        :class="
          mobileView === 'test'
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11'
        "
        @click="mobileView = 'test'"
      >
        {{ t('AI_ASSISTANT.INSTRUCTIONS.TEST_VIEW') }}
      </button>
    </div>

    <div
      class="grid min-w-0 grid-cols-1 items-start gap-6 md:grid-cols-[12rem_minmax(0,1fr)]"
      :class="
        isTestFocused
          ? 'min-[1360px]:grid-cols-1'
          : 'min-[1360px]:grid-cols-[12rem_minmax(30rem,1fr)_minmax(28rem,34rem)]'
      "
    >
      <StructuredInstructionEditor
        :model-value="modelValue"
        :descriptors="descriptors"
        :profile-fields="profileFields"
        :profile-options="profileOptions"
        :compiled-instructions="compiledInstructions"
        :content-length="totalLength"
        :count-label="
          t('AI_ASSISTANT.INSTRUCTIONS.TOTAL_CHAR_COUNT', {
            count: totalLength,
            limit: 50000,
          })
        "
        :empty-preview-label="t('AI_ASSISTANT.INSTRUCTIONS.ALL_SECTIONS_EMPTY')"
        :selector-label="t('AI_ASSISTANT.INSTRUCTIONS.SECTION_SELECTOR')"
        editor-key-prefix="ai-agent-instructions"
        navigator-class="md:h-[calc(100dvh-15rem)] md:min-h-[36rem] md:max-h-[64rem]"
        :navigator-visibility-class="[
          mobileView === 'test' ? 'hidden min-[1360px]:flex' : 'hidden md:flex',
          isTestFocused ? 'min-[1360px]:hidden' : '',
        ]"
        :content-visibility-class="[
          mobileView === 'test' ? 'hidden min-[1360px]:flex' : 'flex',
          isTestFocused ? 'min-[1360px]:hidden' : '',
        ]"
        @update:model-value="emit('update:modelValue', $event)"
      >
        <template #section-footer="{ section }">
          <div
            v-if="section === 'handoff'"
            class="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-n-weak pt-4"
          >
            <div class="flex min-w-0 items-start gap-3">
              <span
                aria-hidden="true"
                class="i-lucide-users mt-0.5 size-4 flex-shrink-0 text-n-slate-10"
              />
              <div class="min-w-0">
                <p class="m-0 text-sm font-medium text-n-slate-12">
                  {{ t('AI_ASSISTANT.CAPABILITIES.HANDOFF') }}
                </p>
                <p class="mb-0 mt-1 break-words text-xs text-n-slate-10">
                  {{ t('AI_ASSISTANT.INSTRUCTIONS.HANDOFF_HELP') }}
                </p>
              </div>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-xs font-medium text-n-teal-11">
                {{ t('AI_ASSISTANT.CAPABILITIES.ALWAYS_ON') }}
              </span>
              <Button
                :label="t('AI_ASSISTANT.INSTRUCTIONS.CONFIGURE')"
                size="sm"
                variant="outline"
                color="slate"
                @click="emit('configureHandoff')"
              />
            </div>
          </div>
        </template>
      </StructuredInstructionEditor>

      <DraftTestPanel
        ref="draftTestPanel"
        class="min-[1360px]:sticky min-[1360px]:top-20"
        :class="
          mobileView === 'edit'
            ? 'hidden min-[1360px]:flex'
            : 'flex md:col-span-2 min-[1360px]:col-span-1'
        "
        :ai-agent-id="aiAgentId"
        :draft-instructions="modelValue"
        :is-draft="isDirty"
        :is-disabled="isDisabled || isOverLimit"
        :is-focused="isTestFocused"
        @tested="emit('tested')"
        @toggle-focus="isTestFocused = !isTestFocused"
      />
    </div>
  </div>
</template>
