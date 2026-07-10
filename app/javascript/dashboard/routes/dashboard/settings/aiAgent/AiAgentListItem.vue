<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import AssistantStatusBadge from './components/AssistantStatusBadge.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['delete']);

const { t } = useI18n();
const router = useRouter();

const inboxCount = computed(
  () => props.agent.agent_bot?.inbox_ids?.length || 0
);

const formattedDate = computed(() => {
  if (!props.agent.updated_at) return '';
  return new Date(props.agent.updated_at).toLocaleDateString();
});

const goToDetail = () => {
  router.push({
    name: 'ai_agent_detail',
    params: { id: props.agent.id },
  });
};
</script>

<template>
  <div
    class="grid grid-cols-1 gap-3 border-b border-n-weak px-4 py-4 last:border-b-0 md:grid-cols-[minmax(0,1fr)_120px_140px_140px_auto] md:items-center"
  >
    <button type="button" class="min-w-0 text-left" @click="goToDetail">
      <span class="block truncate text-sm font-semibold text-n-slate-12">
        {{ agent.name }}
      </span>
      <span class="mt-1 block text-xs text-n-slate-11 md:hidden">
        {{ t('AI_ASSISTANT.LIST.INBOX_COUNT', inboxCount) }}
      </span>
    </button>
    <AssistantStatusBadge :status="agent.lifecycle_status" />
    <span class="hidden text-sm text-n-slate-11 md:block">
      {{ t('AI_ASSISTANT.LIST.INBOX_COUNT', inboxCount) }}
    </span>
    <span class="text-sm text-n-slate-11">
      <span class="mr-1 md:sr-only">
        {{ t('AI_ASSISTANT.LIST.UPDATED') }}
      </span>
      {{ formattedDate }}
    </span>
    <div class="flex items-center justify-end gap-2">
      <Button
        variant="outline"
        color="slate"
        size="sm"
        :label="t('AI_AGENTS.ITEM.EDIT')"
        @click="goToDetail"
      />
      <Button
        icon="i-lucide-trash-2"
        :aria-label="t('AI_AGENTS.ITEM.DELETE')"
        variant="ghost"
        color="ruby"
        size="sm"
        @click="emit('delete', agent)"
      />
    </div>
  </div>
</template>
