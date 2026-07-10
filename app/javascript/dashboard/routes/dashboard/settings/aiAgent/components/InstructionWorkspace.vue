<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import DraftTestPanel from './DraftTestPanel.vue';

const props = defineProps({
  modelValue: { type: Object, required: true },
  aiAgentId: { type: Number, required: true },
  isDirty: { type: Boolean, default: false },
  isDisabled: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue', 'configureHandoff', 'tested']);

const { t } = useI18n();
const mobileView = ref('edit');

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

const editorOptions = [
  'h2',
  'h3',
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
</script>

<template>
  <div class="min-w-0">
    <div
      class="mb-5 grid grid-cols-2 rounded-lg bg-n-alpha-black2 p-1 xl:hidden"
    >
      <button
        type="button"
        class="h-9 rounded-md text-sm font-medium"
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
        class="h-9 rounded-md text-sm font-medium"
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
      class="grid min-w-0 grid-cols-1 items-start gap-8 xl:grid-cols-[minmax(0,1fr)_minmax(22rem,0.58fr)]"
    >
      <main
        class="min-w-0"
        :class="mobileView === 'test' ? 'hidden xl:block' : ''"
      >
        <header class="mb-6">
          <h2 class="m-0 text-xl font-semibold text-n-slate-12">
            {{ t('AI_ASSISTANT.INSTRUCTIONS.TITLE') }}
          </h2>
          <p class="mb-0 mt-1 max-w-3xl text-sm text-n-slate-11">
            {{ t('AI_ASSISTANT.INSTRUCTIONS.DESCRIPTION') }}
          </p>
        </header>

        <section class="border-y border-n-weak py-5">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TITLE') }}
          </h3>
          <p class="mb-4 mt-1 text-sm text-n-slate-11">
            {{ t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.DESCRIPTION') }}
          </p>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
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
        </section>

        <section class="py-5">
          <Editor
            :model-value="modelValue.content"
            editor-key="ai-agent-instructions"
            :placeholder="t('AI_ASSISTANT.INSTRUCTIONS.DOCUMENT_PLACEHOLDER')"
            :max-length="50000"
            show-character-count
            :enable-canned-responses="false"
            variant="article"
            :enabled-menu-options="editorOptions"
            :min-height="32"
            :max-height="60"
            @update:model-value="updateDocument({ content: $event })"
          />
        </section>

        <section
          class="flex flex-wrap items-center justify-between gap-3 border-y border-n-weak py-4"
        >
          <div class="flex min-w-0 items-start gap-3">
            <span
              class="i-lucide-users mt-0.5 size-4 flex-shrink-0 text-n-slate-10"
            />
            <div>
              <p class="m-0 text-sm font-medium text-n-slate-12">
                {{ t('AI_ASSISTANT.CAPABILITIES.HANDOFF') }}
              </p>
              <p class="mb-0 mt-1 text-xs text-n-slate-10">
                {{ t('AI_ASSISTANT.INSTRUCTIONS.HANDOFF_HELP') }}
              </p>
            </div>
          </div>
          <div class="flex items-center gap-2">
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
        </section>
      </main>

      <DraftTestPanel
        class="xl:sticky xl:top-4"
        :class="mobileView === 'edit' ? 'hidden xl:flex' : ''"
        :ai-agent-id="aiAgentId"
        :draft-instructions="modelValue"
        :is-draft="isDirty"
        :is-disabled="isDisabled"
        @tested="emit('tested')"
      />
    </div>
  </div>
</template>
