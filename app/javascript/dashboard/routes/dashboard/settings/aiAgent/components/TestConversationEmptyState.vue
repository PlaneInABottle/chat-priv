<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'list',
    validator: value => ['list', 'chat'].includes(value),
  },
});

const { t } = useI18n();

const message = computed(() => {
  return props.type === 'list'
    ? t('AI_AGENT.TEST_CONVERSATIONS.EMPTY')
    : t('AI_AGENT.TEST_CONVERSATIONS.EMPTY_CHAT');
});

const iconClass = computed(() => {
  return props.type === 'list'
    ? 'i-lucide-message-square-plus'
    : 'i-lucide-message-square';
});
</script>

<template>
  <div
    class="flex flex-col items-center justify-center h-full gap-3 p-6 text-center"
  >
    <div
      class="flex items-center justify-center w-12 h-12 rounded-full bg-n-slate-3 dark:bg-n-slate-8"
    >
      <Icon :icon="iconClass" class="text-n-slate-11 size-6" />
    </div>
    <p class="text-sm text-n-slate-11 max-w-[16rem]">
      {{ message }}
    </p>
  </div>
</template>
