<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  status: { type: String, default: 'draft' },
});

const { t } = useI18n();
const classes = computed(
  () =>
    ({
      active: 'bg-n-teal-3 text-n-teal-11',
      paused: 'bg-n-amber-3 text-n-amber-11',
      draft: 'bg-n-slate-3 text-n-slate-11',
    })[props.status] || 'bg-n-slate-3 text-n-slate-11'
);
</script>

<template>
  <span
    class="inline-flex w-fit items-center rounded-md px-2 py-1 text-xs font-medium"
    :class="classes"
  >
    {{ t(`AI_ASSISTANT.STATUS.${status.toUpperCase()}`) }}
  </span>
</template>
