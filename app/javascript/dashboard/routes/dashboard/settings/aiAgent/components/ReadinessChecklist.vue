<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  readiness: { type: Object, default: () => ({ checks: [] }) },
});

const { t } = useI18n();
const incompleteChecks = computed(() =>
  (props.readiness?.checks || []).filter(check => !check.complete)
);
</script>

<template>
  <section
    class="flex flex-col gap-3 border-y border-n-weak py-4 sm:flex-row sm:items-start sm:justify-between"
    aria-labelledby="readiness-title"
  >
    <div class="max-w-xl">
      <h3
        id="readiness-title"
        class="m-0 text-sm font-semibold text-n-slate-12"
      >
        {{ t('AI_ASSISTANT.READINESS.TITLE') }}
      </h3>
      <p class="mb-0 mt-1 text-sm text-n-slate-11">
        {{ t('AI_ASSISTANT.READINESS.DESCRIPTION') }}
      </p>
    </div>
    <ul class="m-0 flex list-none flex-col gap-2 p-0 sm:min-w-64">
      <li
        v-for="check in incompleteChecks"
        :key="check.key"
        class="flex items-start gap-2 text-sm text-n-slate-12"
      >
        <Icon
          icon="i-lucide-circle-alert"
          class="mt-0.5 size-4 flex-shrink-0 text-n-amber-10"
        />
        <span>
          {{ t(`AI_ASSISTANT.READINESS.${check.key.toUpperCase()}`) }}
        </span>
      </li>
    </ul>
  </section>
</template>
