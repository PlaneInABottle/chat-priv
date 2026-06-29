<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  count: {
    type: [Number, String],
    required: true,
  },
  variant: {
    type: String,
    default: 'slate',
    validator: v => ['teal', 'slate', 'alert'].includes(v),
  },
  size: {
    type: String,
    default: 'sm',
    validator: v => ['sm', 'md'].includes(v),
  },
  overflowThreshold: {
    type: Number,
    default: 99,
  },
});

const { t } = useI18n();

const normalizedCount = computed(() => {
  const count = Number(props.count);
  return Number.isFinite(count) && count > 0 ? count : 0;
});

const displayCount = computed(() => {
  if (normalizedCount.value > props.overflowThreshold) {
    return `${props.overflowThreshold}+`;
  }
  return String(normalizedCount.value);
});

const variantClasses = computed(() => {
  const variants = {
    teal: 'bg-n-teal-9 text-white',
    slate: 'bg-n-slate-4 text-n-slate-12 dark:bg-n-slate-5',
    alert: 'bg-n-ruby-9 text-white',
  };
  return variants[props.variant];
});

const sizeClasses = computed(() => {
  const sizes = {
    sm: 'h-4 min-w-4 max-w-5',
    md: 'h-5 min-w-5',
  };
  return sizes[props.size];
});
</script>

<template>
  <span
    v-if="normalizedCount > 0"
    class="inline-grid place-items-center rounded-full px-1 w-fit font-medium text-xxs leading-3 flex-shrink-0"
    :class="[variantClasses, sizeClasses]"
  >
    {{ displayCount }}
  </span>
  <span v-else class="hidden" />
</template>
