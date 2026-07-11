<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import AiImprovementUsageAPI from 'dashboard/api/aiImprovementUsage';
import { useAlert } from 'dashboard/composables';

defineProps({
  compact: { type: Boolean, default: false },
});
const emit = defineEmits(['loaded']);
const { t } = useI18n();
const usage = ref(null);
const isLoading = ref(false);
const numberFormatter = new Intl.NumberFormat();

const summaryLabel = computed(() => {
  if (!usage.value) return '';
  if (usage.value.unlimited) {
    return t('AI_ASSISTANT.IMPROVEMENT_CREDITS.UNLIMITED');
  }

  const resetDate = new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
  }).format(new Date(usage.value.reset_at));
  return t('AI_ASSISTANT.IMPROVEMENT_CREDITS.SUMMARY', {
    remaining: numberFormatter.format(usage.value.remaining_credits),
    limit: numberFormatter.format(usage.value.limit_credits),
    date: resetDate,
  });
});

const committedCredits = computed(() => {
  if (!usage.value) return 0;

  return usage.value.used_credits + usage.value.reserved_credits;
});

const progress = computed(() => {
  if (!usage.value || usage.value.unlimited) return 0;

  return Math.min(
    100,
    Math.round((committedCredits.value / usage.value.limit_credits) * 100)
  );
});

const progressClass = computed(() => {
  if (usage.value?.status === 'exhausted') return 'bg-n-ruby-9';
  if (usage.value?.status === 'warning') return 'bg-n-amber-9';
  return 'bg-n-teal-9';
});

const load = async () => {
  isLoading.value = true;
  try {
    const response = await AiImprovementUsageAPI.get();
    usage.value = response.data;
    emit('loaded', response.data);
  } catch {
    useAlert(t('AI_ASSISTANT.IMPROVEMENT_CREDITS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
defineExpose({ refresh: load });
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-2 border-n-weak"
    :class="compact ? 'border-t pt-3' : 'border-y py-3'"
    :aria-label="t('AI_ASSISTANT.IMPROVEMENT_CREDITS.TITLE')"
    data-test-id="improvement-credits-summary"
  >
    <div class="flex min-w-0 flex-wrap items-center justify-between gap-2">
      <span
        class="inline-flex min-w-0 items-center gap-2 text-sm font-medium text-n-slate-12"
      >
        <span aria-hidden="true" class="i-lucide-gauge size-4 flex-shrink-0" />
        {{ t('AI_ASSISTANT.IMPROVEMENT_CREDITS.TITLE') }}
      </span>
      <span v-if="isLoading" class="text-xs text-n-slate-10">
        {{ t('AI_ASSISTANT.IMPROVEMENT_CREDITS.LOADING') }}
      </span>
      <span
        v-else-if="usage"
        class="text-xs text-n-slate-11"
        aria-live="polite"
      >
        {{ summaryLabel }}
      </span>
    </div>
    <p v-if="!compact" class="m-0 text-xs text-n-slate-10">
      {{ t('AI_ASSISTANT.IMPROVEMENT_CREDITS.DESCRIPTION') }}
    </p>
    <div
      v-if="usage && !usage.unlimited"
      class="h-1.5 w-full overflow-hidden rounded-full bg-n-alpha-3"
      role="progressbar"
      :aria-label="summaryLabel"
      :aria-valuenow="committedCredits"
      aria-valuemin="0"
      :aria-valuemax="usage.limit_credits"
    >
      <div
        class="h-full rounded-full transition-[width] duration-200 motion-reduce:transition-none"
        :class="progressClass"
        :style="{ width: `${progress}%` }"
      />
    </div>
  </section>
</template>
