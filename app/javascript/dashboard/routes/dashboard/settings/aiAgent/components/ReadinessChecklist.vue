<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  readiness: { type: Object, default: () => ({ checks: [] }) },
});

const { t } = useI18n();
</script>

<template>
  <section
    class="rounded-lg border border-n-weak p-4"
    aria-labelledby="readiness-title"
  >
    <h3 id="readiness-title" class="m-0 text-sm font-semibold text-n-slate-12">
      {{ t('AI_ASSISTANT.READINESS.TITLE') }}
    </h3>
    <p class="mb-0 mt-1 text-sm text-n-slate-11">
      {{ t('AI_ASSISTANT.READINESS.DESCRIPTION') }}
    </p>
    <ul class="m-0 mt-4 flex list-none flex-col gap-3 p-0">
      <li
        v-for="check in readiness.checks"
        :key="check.key"
        class="flex items-start gap-2 text-sm"
      >
        <Icon
          :icon="check.complete ? 'i-lucide-circle-check' : 'i-lucide-circle'"
          class="mt-0.5 size-4 flex-shrink-0"
          :class="check.complete ? 'text-n-teal-10' : 'text-n-slate-9'"
        />
        <span :class="check.complete ? 'text-n-slate-11' : 'text-n-slate-12'">
          {{ t(`AI_ASSISTANT.READINESS.${check.key.toUpperCase()}`) }}
        </span>
      </li>
    </ul>
  </section>
</template>
