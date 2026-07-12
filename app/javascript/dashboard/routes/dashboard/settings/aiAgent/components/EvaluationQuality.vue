<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  quality: { type: Object, default: null },
});

const { t } = useI18n();

const rows = computed(() => {
  if (!props.quality) return [];

  const releaseRows = (props.quality.releases || []).map(release => ({
    key: `release-${release.id}`,
    label: t('AI_ASSISTANT.EVALUATIONS.QUALITY.VERSION', {
      version: release.revision,
    }),
    current: release.current,
    live: release.live,
    evaluation: release.evaluation,
    activity: release.activity,
  }));

  const showDraft =
    props.quality.draft?.differs_from_live || releaseRows.length === 0;
  if (!showDraft) return releaseRows;

  return [
    {
      key: 'draft',
      label: t('AI_ASSISTANT.EVALUATIONS.QUALITY.DRAFT'),
      draft: true,
      evaluation: props.quality.draft?.evaluation,
      activity: null,
    },
    ...releaseRows,
  ];
});

const evaluationLabel = evaluation => {
  if (!evaluation) return t('AI_ASSISTANT.EVALUATIONS.QUALITY.NOT_EVALUATED');

  return t('AI_ASSISTANT.EVALUATIONS.QUALITY.EVALUATION_SCORE', {
    passed: evaluation.passed_count,
    total: evaluation.total_count,
    rate: evaluation.pass_rate ?? 0,
  });
};

const activityLabel = (activity, key) => {
  if (!activity) return t('AI_ASSISTANT.EVALUATIONS.QUALITY.NOT_LIVE');

  return new Intl.NumberFormat().format(activity[key] || 0);
};

const handoffLabel = activity => {
  if (!activity) return t('AI_ASSISTANT.EVALUATIONS.QUALITY.NOT_LIVE');
  if (!activity.conversations) {
    return t('AI_ASSISTANT.EVALUATIONS.QUALITY.NO_ACTIVITY');
  }

  return t('AI_ASSISTANT.EVALUATIONS.QUALITY.HANDOFF_VALUE', {
    count: new Intl.NumberFormat().format(activity.handoffs || 0),
    rate: activity.handoff_rate ?? 0,
  });
};
</script>

<template>
  <section
    class="min-w-0 border-b border-n-weak pb-6"
    :class="{ hidden: !rows.length }"
    :aria-hidden="!rows.length"
    aria-labelledby="evaluation-quality-title"
  >
    <h3
      id="evaluation-quality-title"
      class="m-0 text-sm font-semibold text-n-slate-12"
    >
      {{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.TITLE') }}
    </h3>
    <p class="mb-0 mt-1 max-w-3xl text-xs text-n-slate-10">
      {{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.DESCRIPTION') }}
    </p>

    <div
      class="mt-4 hidden grid-cols-[minmax(0,1.3fr)_repeat(4,minmax(0,1fr))] gap-4 border-b border-n-weak pb-2 text-xs font-medium text-n-slate-10 lg:grid"
      aria-hidden="true"
    >
      <span>{{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.VERSION_HEADER') }}</span>
      <span>{{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.EVALUATION_HEADER') }}</span>
      <span>{{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.CONVERSATIONS') }}</span>
      <span>{{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.AI_REPLIES') }}</span>
      <span>{{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.HANDOFFS') }}</span>
    </div>

    <div class="flex min-w-0 flex-col">
      <div
        v-for="row in rows"
        :key="row.key"
        class="grid min-w-0 grid-cols-2 gap-x-4 gap-y-3 border-b border-n-weak py-4 last:border-b-0 lg:grid-cols-[minmax(0,1.3fr)_repeat(4,minmax(0,1fr))] lg:items-center lg:gap-y-0"
      >
        <div class="col-span-2 min-w-0 lg:col-span-1">
          <span class="flex flex-wrap items-center gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ row.label }}
            </span>
            <span
              v-if="row.live"
              class="rounded-md bg-n-teal-3 px-2 py-0.5 text-xs font-medium text-n-teal-11"
            >
              {{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.LIVE') }}
            </span>
            <span
              v-else-if="row.current"
              class="rounded-md bg-n-slate-3 px-2 py-0.5 text-xs font-medium text-n-slate-11"
            >
              {{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.CURRENT') }}
            </span>
            <span
              v-else-if="row.draft"
              class="rounded-md bg-n-amber-3 px-2 py-0.5 text-xs font-medium text-n-amber-11"
            >
              {{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.NOT_PUBLISHED') }}
            </span>
          </span>
        </div>

        <div class="min-w-0 text-sm text-n-slate-12">
          <span class="mb-1 block text-xs text-n-slate-10 lg:hidden">
            {{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.EVALUATION_HEADER') }}
          </span>
          <span class="break-words">{{ evaluationLabel(row.evaluation) }}</span>
        </div>
        <div class="min-w-0 text-sm text-n-slate-12">
          <span class="mb-1 block text-xs text-n-slate-10 lg:hidden">
            {{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.CONVERSATIONS') }}
          </span>
          {{ activityLabel(row.activity, 'conversations') }}
        </div>
        <div class="min-w-0 text-sm text-n-slate-12">
          <span class="mb-1 block text-xs text-n-slate-10 lg:hidden">
            {{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.AI_REPLIES') }}
          </span>
          {{ activityLabel(row.activity, 'ai_replies') }}
        </div>
        <div class="min-w-0 text-sm text-n-slate-12">
          <span class="mb-1 block text-xs text-n-slate-10 lg:hidden">
            {{ t('AI_ASSISTANT.EVALUATIONS.QUALITY.HANDOFFS') }}
          </span>
          <span class="break-words">{{ handoffLabel(row.activity) }}</span>
        </div>
      </div>
    </div>
  </section>
</template>
