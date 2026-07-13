<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import EvaluationSuite from './EvaluationSuite.vue';
import ImprovementCreditsSummary from './ImprovementCreditsSummary.vue';
import LearningSuggestions from './LearningSuggestions.vue';

const props = defineProps({
  aiAgentId: { type: Number, required: true },
  hasUnsavedInstructions: { type: Boolean, default: false },
  autoLearningEnabled: { type: Boolean, default: false },
  mode: {
    type: String,
    required: true,
    validator: value => ['evaluations', 'learnings'].includes(value),
  },
});

const emit = defineEmits(['draftUpdated']);
const creditsSummaryRef = ref(null);
const improvementUsage = ref(null);

const { t } = useI18n();
const router = useRouter();
const tabs = computed(() => [
  {
    label: t('AI_ASSISTANT.IMPROVE.EVALUATIONS'),
    value: 'evaluations',
  },
  {
    label: t('AI_ASSISTANT.IMPROVE.LEARNINGS'),
    value: 'learnings',
  },
]);
const activeTabIndex = computed(() =>
  tabs.value.findIndex(tab => tab.value === props.mode)
);

const handleTabChange = tab => {
  router.push({
    name:
      tab.value === 'learnings'
        ? 'ai_agent_learning_suggestions'
        : 'ai_agent_evaluations',
    params: { id: props.aiAgentId },
  });
};

const refreshCredits = () => creditsSummaryRef.value?.refresh();
const creditsExhausted = computed(
  () => improvementUsage.value?.status === 'exhausted'
);
const handleImprovementUsageLoaded = usage => {
  improvementUsage.value = usage;
};
</script>

<template>
  <div class="flex min-w-0 flex-col gap-6">
    <div class="border-b border-n-weak pb-3">
      <TabBar
        :tabs="tabs"
        :initial-active-tab="activeTabIndex"
        @tab-changed="handleTabChange"
      />
    </div>
    <div
      v-if="hasUnsavedInstructions"
      class="flex items-start gap-2 rounded-lg border border-n-amber-5 bg-n-amber-2 p-3 text-sm text-n-amber-11"
    >
      <span
        aria-hidden="true"
        class="i-lucide-file-warning mt-0.5 size-4 flex-shrink-0"
      />
      <p class="m-0">{{ t('AI_ASSISTANT.IMPROVE.SAVE_DRAFT_FIRST') }}</p>
    </div>
    <ImprovementCreditsSummary
      ref="creditsSummaryRef"
      @loaded="handleImprovementUsageLoaded"
    />
    <EvaluationSuite
      v-if="mode === 'evaluations'"
      :ai-agent-id="aiAgentId"
      :has-unsaved-instructions="hasUnsavedInstructions"
      :credits-exhausted="creditsExhausted"
      @usage-changed="refreshCredits"
    />
    <LearningSuggestions
      v-else
      :ai-agent-id="aiAgentId"
      :has-unsaved-instructions="hasUnsavedInstructions"
      :auto-learning-enabled="autoLearningEnabled"
      @draft-updated="emit('draftUpdated', $event)"
    />
  </div>
</template>
