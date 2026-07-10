<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import DraftTestPanel from './DraftTestPanel.vue';
import InstructionSectionEditor from './InstructionSectionEditor.vue';
import { STANDARD_SECTION_KEYS } from '../helpers/instructionDocument';

const props = defineProps({
  modelValue: { type: Object, required: true },
  aiAgentId: { type: Number, required: true },
  isDirty: { type: Boolean, default: false },
  isDisabled: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue', 'configureHandoff', 'tested']);

const { t } = useI18n();

const profileOptions = computed(() => ({
  language: [
    [
      'same_as_customer',
      t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.LANGUAGE.SAME_AS_CUSTOMER'),
    ],
    ['tr', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.LANGUAGE.TURKISH')],
    ['en', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.LANGUAGE.ENGLISH')],
  ],
  tone: [
    ['natural', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TONE.NATURAL')],
    ['friendly', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TONE.FRIENDLY')],
    ['professional', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TONE.PROFESSIONAL')],
    ['warm', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TONE.WARM')],
    ['concise', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.TONE.CONCISE')],
  ],
  formality: [
    ['balanced', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.FORMALITY.BALANCED')],
    ['casual', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.FORMALITY.CASUAL')],
    ['formal', t('AI_ASSISTANT.INSTRUCTIONS.PROFILE.FORMALITY.FORMAL')],
  ],
  response_length: [
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

const standardSectionCopy = computed(() => ({
  identity: {
    title: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.IDENTITY.TITLE'),
    description: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.IDENTITY.DESCRIPTION'),
  },
  business_context: {
    title: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.BUSINESS_CONTEXT.TITLE'),
    description: t(
      'AI_ASSISTANT.INSTRUCTIONS.SECTIONS.BUSINESS_CONTEXT.DESCRIPTION'
    ),
  },
  tasks: {
    title: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.TASKS.TITLE'),
    description: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.TASKS.DESCRIPTION'),
  },
  rules: {
    title: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.RULES.TITLE'),
    description: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.RULES.DESCRIPTION'),
  },
  handoff: {
    title: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.HANDOFF.TITLE'),
    description: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.HANDOFF.DESCRIPTION'),
  },
  examples: {
    title: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.EXAMPLES.TITLE'),
    description: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.EXAMPLES.DESCRIPTION'),
  },
  current_instructions: {
    title: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.CURRENT.TITLE'),
    description: t('AI_ASSISTANT.INSTRUCTIONS.SECTIONS.CURRENT.DESCRIPTION'),
  },
}));

const legacySection = computed(() =>
  props.modelValue.sections.find(
    section => section.key === 'current_instructions'
  )
);

const sectionCopy = section => {
  if (section.custom) {
    return {
      title: section.title || t('AI_ASSISTANT.INSTRUCTIONS.CUSTOM_SECTION'),
      description: '',
    };
  }

  return (
    standardSectionCopy.value[section.key] || {
      title: section.title || section.key,
      description: '',
    }
  );
};

const updateDocument = changes => {
  emit('update:modelValue', { ...props.modelValue, ...changes });
};

const updateProfile = (key, value) => {
  updateDocument({
    profile: { ...props.modelValue.profile, [key]: value },
  });
};

const updateSection = (index, section) => {
  const sections = [...props.modelValue.sections];
  sections[index] = section;
  updateDocument({ sections });
};

const moveSection = (index, offset) => {
  const targetIndex = index + offset;
  if (targetIndex < 0 || targetIndex >= props.modelValue.sections.length)
    return;

  const sections = [...props.modelValue.sections];
  [sections[index], sections[targetIndex]] = [
    sections[targetIndex],
    sections[index],
  ];
  updateDocument({ sections });
};

const removeSection = index => {
  updateDocument({
    sections: props.modelValue.sections.filter(
      (_, itemIndex) => itemIndex !== index
    ),
  });
};

const addSection = () => {
  const sections = [
    ...props.modelValue.sections,
    {
      key: `custom_${Date.now()}`,
      title: '',
      content: '',
      critical: false,
      custom: true,
    },
  ];
  updateDocument({ sections });
};

const organizeIntoSections = () => {
  const sections = STANDARD_SECTION_KEYS.map(key => ({
    key,
    title: '',
    content: key === 'tasks' ? legacySection.value?.content || '' : '',
    critical: key === 'rules',
    custom: false,
  }));
  updateDocument({ sections });
};
</script>

<template>
  <div
    class="grid min-w-0 grid-cols-1 items-start gap-8 xl:grid-cols-[minmax(0,1fr)_minmax(22rem,0.58fr)]"
  >
    <main class="min-w-0">
      <header class="mb-6">
        <h2 class="m-0 text-xl font-semibold text-n-slate-12">
          {{ t('AI_ASSISTANT.INSTRUCTIONS.TITLE') }}
        </h2>
        <p class="mb-0 mt-1 max-w-3xl text-sm text-n-slate-11">
          {{ t('AI_ASSISTANT.INSTRUCTIONS.DESCRIPTION') }}
        </p>
        <div
          v-if="legacySection"
          class="mt-4 flex flex-wrap items-center justify-between gap-3 border-y border-n-weak py-3"
        >
          <p class="m-0 max-w-2xl text-sm text-n-slate-11">
            {{ t('AI_ASSISTANT.INSTRUCTIONS.ORGANIZE_HELP') }}
          </p>
          <Button
            icon="i-lucide-list-tree"
            :label="t('AI_ASSISTANT.INSTRUCTIONS.ORGANIZE')"
            variant="outline"
            color="slate"
            @click="organizeIntoSections"
          />
        </div>
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

      <div>
        <InstructionSectionEditor
          v-for="(section, index) in modelValue.sections"
          :key="section.key"
          :section="section"
          :title="sectionCopy(section).title"
          :description="sectionCopy(section).description"
          :can-move-up="index > 0"
          :can-move-down="index < modelValue.sections.length - 1"
          @update="updateSection(index, $event)"
          @remove="removeSection(index)"
          @move-up="moveSection(index, -1)"
          @move-down="moveSection(index, 1)"
        >
          <div
            v-if="section.key === 'handoff'"
            class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-n-weak bg-n-alpha-black1 p-3"
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
          </div>
        </InstructionSectionEditor>
      </div>

      <Button
        class="mt-5"
        icon="i-lucide-plus"
        :label="t('AI_ASSISTANT.INSTRUCTIONS.ADD_SECTION')"
        variant="outline"
        color="slate"
        :disabled="modelValue.sections.length >= 20"
        @click="addSection"
      />
    </main>

    <DraftTestPanel
      class="xl:sticky xl:top-4"
      :ai-agent-id="aiAgentId"
      :draft-instructions="modelValue"
      :is-draft="isDirty"
      :is-disabled="isDisabled"
      @tested="emit('tested')"
    />
  </div>
</template>
