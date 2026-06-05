<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  usage: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();

const isLoading = computed(() => !props.usage);
const isUnlimited = computed(() => Boolean(props.usage?.unlimited));
const isExhausted = computed(() => props.usage?.status === 'exhausted');
const isWarning = computed(() => props.usage?.status === 'warning');

const progressPercent = computed(() => {
  if (isLoading.value || isUnlimited.value || !props.usage.limit) return 0;
  return Math.min(
    Math.round((props.usage.used / props.usage.limit) * 100),
    100
  );
});

const remainingText = computed(() => {
  if (isLoading.value) return t('AI_AGENT.USAGE_REPORT.LOADING');
  if (isUnlimited.value) return t('AI_AGENT.USAGE_REPORT.UNLIMITED_REMAINING');

  return t('AI_AGENT.USAGE_REPORT.REMAINING', {
    count: props.usage.remaining,
  });
});

const usageText = computed(() => {
  if (isLoading.value) return t('AI_AGENT.USAGE_REPORT.LOADING');
  if (isUnlimited.value) {
    return t('AI_AGENT.USAGE_REPORT.UNLIMITED_USED', {
      used: props.usage.used,
    });
  }

  return t('AI_AGENT.USAGE_REPORT.USED_OF_LIMIT', {
    used: props.usage.used,
    limit: props.usage.limit,
  });
});

const formatDateTime = value => {
  if (!value) return '-';

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));
};

const resetText = computed(() => formatDateTime(props.usage?.reset_at));

const metrics = computed(() => props.usage?.metrics || {});
const recentEvents = computed(() => props.usage?.recent_events || []);

const cardClasses = computed(() => {
  if (isExhausted.value) {
    return 'border-n-ruby-5 bg-n-ruby-2';
  }

  if (isWarning.value) {
    return 'border-n-amber-5 bg-n-amber-2';
  }

  return 'border-n-weak bg-n-alpha-1';
});

const iconClasses = computed(() => {
  if (isExhausted.value) return 'bg-n-ruby-4 text-n-ruby-11';
  if (isWarning.value) return 'bg-n-amber-4 text-n-amber-11';
  return 'bg-n-blue-3 text-n-brand';
});
</script>

<template>
  <section
    class="flex flex-col gap-5 p-5 rounded-lg border"
    :class="cardClasses"
  >
    <div
      class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between"
    >
      <div class="flex items-start gap-3 min-w-0">
        <div
          class="flex items-center justify-center flex-shrink-0 w-10 h-10 rounded-full"
          :class="iconClasses"
        >
          <Icon
            :icon="isExhausted ? 'i-lucide-circle-alert' : 'i-lucide-gauge'"
            class="size-5"
          />
        </div>
        <div class="min-w-0">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('AI_AGENT.USAGE_REPORT.TITLE') }}
          </h3>
          <p class="m-0 mt-1 text-sm text-n-slate-11">
            {{
              isExhausted
                ? t('AI_AGENT.USAGE_REPORT.EXHAUSTED_HELP')
                : t('AI_AGENT.USAGE_REPORT.HELP')
            }}
          </p>
        </div>
      </div>
      <div class="flex flex-col gap-1 lg:text-right">
        <span class="text-2xl font-semibold text-n-slate-12">
          {{ remainingText }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ usageText }}
        </span>
      </div>
    </div>

    <div
      v-if="!isUnlimited"
      class="h-2 overflow-hidden rounded-full bg-n-slate-4"
    >
      <div
        class="h-full rounded-full"
        :class="
          isExhausted
            ? 'bg-n-ruby-9'
            : isWarning
              ? 'bg-n-amber-9'
              : 'bg-n-brand'
        "
        :style="{ width: `${progressPercent}%` }"
      />
    </div>

    <div
      class="grid grid-cols-1 gap-px overflow-hidden rounded-lg border border-n-weak bg-n-slate-4 md:grid-cols-4"
    >
      <div class="bg-n-alpha-1 p-3">
        <span class="text-xs text-n-slate-11">
          {{ t('AI_AGENT.USAGE_REPORT.RESET_AT') }}
        </span>
        <p class="m-0 mt-1 text-sm font-medium text-n-slate-12">
          {{ resetText }}
        </p>
      </div>
      <div class="bg-n-alpha-1 p-3">
        <span class="text-xs text-n-slate-11">
          {{ t('AI_AGENT.USAGE_REPORT.REUSE_WINDOW') }}
        </span>
        <p class="m-0 mt-1 text-sm font-medium text-n-slate-12">
          {{
            t('AI_AGENT.USAGE_REPORT.HOURS', {
              count: usage?.reuse_window_hours || 24,
            })
          }}
        </p>
      </div>
      <div class="bg-n-alpha-1 p-3">
        <span class="text-xs text-n-slate-11">
          {{ t('AI_AGENT.USAGE_REPORT.AI_REPLIES') }}
        </span>
        <p class="m-0 mt-1 text-sm font-medium text-n-slate-12">
          {{ metrics.ai_replies || 0 }}
        </p>
      </div>
      <div class="bg-n-alpha-1 p-3">
        <span class="text-xs text-n-slate-11">
          {{ t('AI_AGENT.USAGE_REPORT.HANDOFFS') }}
        </span>
        <p class="m-0 mt-1 text-sm font-medium text-n-slate-12">
          {{ metrics.handoffs || 0 }}
        </p>
      </div>
    </div>

    <div class="flex flex-wrap gap-x-4 gap-y-2 text-xs text-n-slate-11">
      <span>
        {{
          t('AI_AGENT.USAGE_REPORT.COUNTED_CONVERSATIONS', {
            count: metrics.counted_conversations || 0,
          })
        }}
      </span>
      <span>
        {{
          t('AI_AGENT.USAGE_REPORT.TOOL_CALLS', {
            count: metrics.tool_calls || 0,
          })
        }}
      </span>
    </div>

    <div v-if="recentEvents.length" class="flex flex-col gap-2">
      <h4 class="m-0 text-xs font-medium uppercase text-n-slate-11">
        {{ t('AI_AGENT.USAGE_REPORT.RECENT_CONVERSATIONS') }}
      </h4>
      <div class="overflow-hidden rounded-lg border border-n-weak bg-n-alpha-1">
        <div
          v-for="event in recentEvents"
          :key="event.id"
          class="grid grid-cols-1 gap-2 border-b border-n-weak p-3 last:border-b-0 md:grid-cols-[1fr_auto]"
        >
          <div class="min-w-0">
            <p class="m-0 truncate text-sm font-medium text-n-slate-12">
              {{
                event.contact_name || t('AI_AGENT.USAGE_REPORT.UNKNOWN_CONTACT')
              }}
            </p>
            <p class="m-0 mt-1 text-xs text-n-slate-11">
              {{
                t('AI_AGENT.USAGE_REPORT.CONVERSATION_LABEL', {
                  id: event.conversation_display_id || event.conversation_id,
                })
              }}
            </p>
          </div>
          <div class="text-xs text-n-slate-11 md:text-right">
            <p class="m-0">
              {{
                t('AI_AGENT.USAGE_REPORT.COUNTED_AT', {
                  time: formatDateTime(event.created_at),
                })
              }}
            </p>
            <p class="m-0 mt-1">
              {{
                t('AI_AGENT.USAGE_REPORT.REUSE_UNTIL', {
                  time: formatDateTime(event.window_ends_at),
                })
              }}
            </p>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
