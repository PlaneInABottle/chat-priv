<script setup>
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import aiAgentAPI from 'dashboard/api/aiAgent';

const props = defineProps({
  aiAgentId: {
    type: Number,
    required: true,
  },
});

const { t } = useI18n();
const logs = ref([]);
const isLoading = ref(false);
const error = ref('');
const filters = ref({ status: '', mode: '', tool_key: '' });

const fetchLogs = async () => {
  isLoading.value = true;
  error.value = '';
  try {
    const { data } = await aiAgentAPI.getToolExecutions(props.aiAgentId, filters.value);
    logs.value = data.payload || [];
  } catch {
    error.value = t('AI_AGENT.TOOL_LOGS.ERROR');
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchLogs);
watch(filters, fetchLogs, { deep: true });
</script>

<template>
  <div class="flex flex-col gap-4">
    <h3 class="text-sm font-medium text-n-slate-12">
      {{ t('AI_AGENT.TOOL_LOGS.TITLE') }}
    </h3>
    <div class="grid grid-cols-1 gap-3 md:grid-cols-3">
      <select v-model="filters.status" class="rounded border border-n-weak p-2">
        <option value="">{{ t('AI_AGENT.TOOL_LOGS.FILTERS.ALL_STATUSES') }}</option>
        <option value="executed">{{ t('AI_AGENT.TOOL_LOGS.STATUS.EXECUTED') }}</option>
        <option value="error">{{ t('AI_AGENT.TOOL_LOGS.STATUS.ERROR') }}</option>
        <option value="rejected">{{ t('AI_AGENT.TOOL_LOGS.STATUS.REJECTED') }}</option>
      </select>
      <select v-model="filters.mode" class="rounded border border-n-weak p-2">
        <option value="">{{ t('AI_AGENT.TOOL_LOGS.FILTERS.ALL_MODES') }}</option>
        <option value="test">{{ t('AI_AGENT.TOOL_LOGS.MODE.TEST') }}</option>
        <option value="live">{{ t('AI_AGENT.TOOL_LOGS.MODE.LIVE') }}</option>
      </select>
      <input v-model="filters.tool_key" class="rounded border border-n-weak p-2" :placeholder="t('AI_AGENT.TOOL_LOGS.FILTERS.TOOL_KEY')" />
    </div>
    <p v-if="isLoading" class="text-sm text-n-slate-11">
      {{ t('AI_AGENT.TOOL_LOGS.LOADING') }}
    </p>
    <p v-else-if="error" class="text-sm text-n-ruby-11">
      {{ error }}
    </p>
    <p v-else-if="logs.length === 0" class="text-sm text-n-slate-11">
      {{ t('AI_AGENT.TOOL_LOGS.EMPTY') }}
    </p>
    <div v-else class="flex flex-col gap-3">
      <article v-for="log in logs" :key="log.id" class="rounded-lg border border-n-weak p-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div>
            <p class="text-sm font-medium text-n-slate-12">{{ log.tool_key }}</p>
            <p class="text-xs text-n-slate-11">{{ log.mode }} · {{ log.created_at }}</p>
          </div>
          <span class="rounded-full bg-n-alpha-black1 px-2 py-1 text-xs font-medium">{{ log.status }}</span>
        </div>
        <p v-if="log.error_code" class="mt-2 text-sm text-n-ruby-11">
          {{ log.error_code }}<span v-if="log.error_message">: {{ log.error_message }}</span>
        </p>
        <a v-if="log.conversation_url" :href="log.conversation_url" class="mt-2 inline-flex text-sm text-n-brand underline">
          {{ t('AI_AGENT.TOOL_LOGS.CONVERSATION_LINK', { id: log.conversation_display_id }) }}
        </a>
        <div class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2">
          <pre class="overflow-auto rounded bg-n-alpha-black1 p-3 text-xs"><code>{{ JSON.stringify(log.arguments || {}, null, 2) }}</code></pre>
          <pre class="overflow-auto rounded bg-n-alpha-black1 p-3 text-xs"><code>{{ JSON.stringify(log.result || {}, null, 2) }}</code></pre>
        </div>
      </article>
    </div>
  </div>
</template>
