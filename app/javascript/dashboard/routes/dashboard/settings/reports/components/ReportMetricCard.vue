<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useI18n } from 'vue-i18n';

defineProps({
  label: {
    type: String,
    required: true,
  },
  value: {
    type: String,
    required: true,
  },
  infoText: {
    type: String,
    required: true,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
</script>

<template>
  <div
    data-test-id="reportMetricContainer"
    :class="{
      'grayscale pointer-events-none opacity-30': disabled,
    }"
  >
    <h3 class="flex items-center m-0 text-sm font-medium text-n-slate-11">
      <span data-test-id="reportMetricLabel">{{ label }}</span>
      <span
        v-tooltip="infoText"
        data-test-id="reportMetricInfo"
        class="text-n-slate-11 my-0 mx-1 mt-0.5 cursor-help"
        :aria-label="t('REPORT.GROUP.ADMIN_REPORTS.HEADER')"
        role="tooltip"
        tabindex="0"
      >
        <Icon icon="i-lucide-info" class="size-3.5" />
      </span>
    </h3>
    <h4
      data-test-id="reportMetricValue"
      class="mt-1 mb-0 text-2xl text-n-slate-12"
    >
      {{ value }}
    </h4>
  </div>
</template>
