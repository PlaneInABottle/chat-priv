<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import DraftTestPanel from './DraftTestPanel.vue';
import InstructionSectionNavigator from './InstructionSectionNavigator.vue';
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
const { formatMessage } = useMessageFormatter();
const mobileView = ref('edit');
const selectedSection = ref('profile');

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
    ['warm', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TONE.WARM')],
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
    configured: isSectionConfigured(key),
    statusLabel: t(sectionStatusLabelKey(key)),
  }))
);

const selectedItem = computed(() =>
  sectionItems.value.find(item => item.key === selectedSection.value)
);

const totalLength = computed(() => instructionContentLength(props.modelValue));
const isOverLimit = computed(() => totalLength.value > 50000);
const compiledInstructions = computed(() =>
  compileInstructionDocument(props.modelValue)
);
const formattedInstructions = computed(() =>
  formatMessage(compiledInstructions.value, false, false, false)
);

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
      class="grid min-w-0 grid-cols-1 items-start gap-6 md:grid-cols-[12rem_minmax(0,1fr)] min-[1360px]:grid-cols-[12rem_minmax(30rem,1fr)_minmax(24rem,28rem)]"
    >
      <InstructionSectionNavigator
        :items="sectionItems"
        :selected-key="selectedSection"
        :class="
          mobileView === 'test'
            ? 'hidden min-[1360px]:flex min-[1360px]:h-[calc(100dvh-22rem)] min-[1360px]:min-h-[26rem] min-[1360px]:max-h-[48rem]'
            : 'hidden md:flex md:h-[calc(100dvh-22rem)] md:min-h-[26rem] md:max-h-[48rem]'
        "
        @select="selectedSection = $event"
      />

      <section
        class="min-h-[32rem] min-w-0 flex-col md:h-[calc(100dvh-22rem)] md:min-h-[26rem] md:max-h-[48rem] md:overflow-hidden"
        :class="mobileView === 'test' ? 'hidden min-[1360px]:flex' : 'flex'"
      >
        <label class="mb-4 flex flex-col gap-1 text-sm font-medium md:hidden">
          {{ t('AI_ASSISTANT.INSTRUCTIONS.SECTION_SELECTOR') }}
          <select
            v-model="selectedSection"
            class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal"
          >
            <option
              v-for="item in sectionItems"
              :key="item.key"
              :value="item.key"
            >
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
          v-if="selectedSection === 'all'"
          class="min-h-0 flex-1 overflow-y-auto py-5 pr-1"
        >
          <div
            v-if="compiledInstructions"
            v-dompurify-html="formattedInstructions"
            class="prose prose-sm max-w-none break-words text-n-slate-12 dark:prose-invert prose-headings:scroll-mt-4 prose-headings:text-n-slate-12 prose-h2:mb-2 prose-h2:mt-6 prose-h2:border-b prose-h2:border-n-weak prose-h2:pb-2 prose-p:leading-relaxed prose-li:leading-relaxed"
          />
          <div v-else class="py-12 text-center text-sm text-n-slate-10">
            {{ t('AI_ASSISTANT.INSTRUCTIONS.ALL_SECTIONS_EMPTY') }}
          </div>
        </div>

        <div
          v-else-if="selectedSection === 'profile'"
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
            :model-value="modelValue.sections[selectedSection] || ''"
            :editor-key="`ai-agent-instructions-${selectedSection}`"
            :aria-label="selectedItem.title"
            :placeholder="
              t(
                `AI_ASSISTANT.INSTRUCTIONS.SECTIONS.${selectedSection.toUpperCase()}.PLACEHOLDER`
              )
            "
            :max-length="50000"
            :show-character-count="false"
            :enable-canned-responses="false"
            variant="article"
            :enabled-menu-options="editorOptions"
            min-height="10rem"
            max-height="clamp(10rem, calc(100dvh - 37rem), 28rem)"
            @update:model-value="updateSection"
          />

          <div
            v-if="selectedSection === 'handoff'"
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
        </div>

        <p
          class="m-0 flex-shrink-0 border-t border-n-weak pt-3 text-right text-xs"
          :class="isOverLimit ? 'text-n-ruby-11' : 'text-n-slate-10'"
        >
          {{
            t('AI_ASSISTANT.INSTRUCTIONS.TOTAL_CHAR_COUNT', {
              count: totalLength,
              limit: 50000,
            })
          }}
        </p>
      </section>

      <DraftTestPanel
        class="min-[1360px]:sticky min-[1360px]:top-4"
        :class="
          mobileView === 'edit'
            ? 'hidden min-[1360px]:flex'
            : 'flex md:col-span-2 min-[1360px]:col-span-1'
        "
        :ai-agent-id="aiAgentId"
        :draft-instructions="modelValue"
        :is-draft="isDirty"
        :is-disabled="isDisabled || isOverLimit"
        @tested="emit('tested')"
      />
    </div>
  </div>
</template>
