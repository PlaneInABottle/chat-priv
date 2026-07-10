<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import EvaluationSuite from './EvaluationSuite.vue';
import LearningSuggestions from './LearningSuggestions.vue';

const props = defineProps({
  aiAgentId: { type: Number, required: true },
  mode: {
    type: String,
    required: true,
    validator: value => ['evaluations', 'learnings'].includes(value),
  },
});

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
    <EvaluationSuite v-if="mode === 'evaluations'" :ai-agent-id="aiAgentId" />
    <LearningSuggestions v-else :ai-agent-id="aiAgentId" />
  </div>
</template>
