<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import aiAgentAPI from 'dashboard/api/aiAgent';
import ToolLogsTable from 'dashboard/components-next/AI/ToolLogsTable.vue';

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
const filters = ref({ status: '', tool_key: '', date_range: '' });
const sort = ref({ sort: 'created_at', direction: 'desc' });

const toolOptions = [
  { key: 'human_handoff', name: 'human_handoff' },
  { key: 'ikas_lookup_order', name: 'ikas_lookup_order' },
];

const requestParams = computed(() => ({
  ...filters.value,
  sort: sort.value.sort,
  direction: sort.value.direction,
}));

const fetchLogs = async () => {
  isLoading.value = true;
  error.value = '';
  try {
    const { data } = await aiAgentAPI.getToolExecutions(
      props.aiAgentId,
      requestParams.value
    );
    logs.value = data.payload || [];
  } catch {
    error.value = t('AI_AGENT.TOOL_LOGS.ERROR');
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchLogs);
watch([filters, sort], fetchLogs, { deep: true });

const updateFilters = nextFilters => {
  filters.value = nextFilters;
};

const updateSort = nextSort => {
  sort.value = nextSort;
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <h3 class="text-sm font-medium text-n-slate-12">
      {{ t('AI_AGENT.TOOL_LOGS.TITLE') }}
    </h3>
    <ToolLogsTable
      :rows="logs"
      :filters="filters"
      :sort="sort"
      :loading="isLoading"
      :error="error"
      :tool-options="toolOptions"
      @update:filters="updateFilters"
      @update:sort="updateSort"
      @refresh="fetchLogs"
    />
  </div>
</template>
