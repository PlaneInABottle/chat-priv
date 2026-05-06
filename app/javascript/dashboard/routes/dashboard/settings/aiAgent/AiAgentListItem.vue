<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['delete']);

const { t } = useI18n();

const inboxCount = computed(() => props.agent.inbox_ids?.length || 0);

const formattedDate = computed(() => {
  if (!props.agent.created_at) return '';
  return new Date(props.agent.created_at).toLocaleDateString();
});
</script>

<template>
  <div
    class="flex flex-col gap-4 p-4 rounded-lg border border-n-weak dark:border-n-weak bg-n-alpha-1"
  >
    <div class="flex items-start justify-between">
      <div class="flex flex-col gap-1">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ agent.name }}
        </span>
        <span
          class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium w-fit"
          :class="
            agent.enabled
              ? 'bg-n-green-3 text-n-green-11'
              : 'bg-n-slate-3 text-n-slate-11'
          "
        >
          {{
            agent.enabled
              ? t('AI_AGENTS.ITEM.STATUS_ENABLED')
              : t('AI_AGENTS.ITEM.STATUS_DISABLED')
          }}
        </span>
      </div>
    </div>

    <div class="flex flex-col gap-1 text-sm text-n-slate-11">
      <span>
        {{ t('AI_AGENTS.ITEM.INBOXES_COUNT', { count: inboxCount }) }}
      </span>
      <span v-if="formattedDate"> {{ formattedDate }} </span>
    </div>

    <div class="flex items-center gap-2 mt-auto">
      <router-link
        :to="{
          name: 'ai_agent_detail',
          params: { id: agent.id },
        }"
        class="flex-1"
      >
        <Button
          variant="faded"
          color="slate"
          size="small"
          class="w-full"
          :label="t('AI_AGENTS.ITEM.EDIT')"
        />
      </router-link>
      <Button
        variant="faded"
        color="ruby"
        size="small"
        class="flex-1"
        :label="t('AI_AGENTS.ITEM.DELETE')"
        @click="emit('delete', agent)"
      />
    </div>
  </div>
</template>
