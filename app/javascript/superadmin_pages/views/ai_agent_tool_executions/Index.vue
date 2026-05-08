<script setup>
import { ref } from 'vue';
import ToolLogsTable from 'dashboard/components-next/AI/ToolLogsTable.vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const rows = ref(props.componentData.initial_payload?.payload || []);
const filters = ref(props.componentData.initial_payload?.meta?.filters || {});
const sort = ref({
  sort: filters.value.sort || 'created_at',
  direction: filters.value.direction || 'desc',
});
const isLoading = ref(false);
const error = ref('');

const csrfToken = () =>
  document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');

const buildQueryParams = () => {
  const params = new URLSearchParams();
  Object.entries({ ...filters.value, ...sort.value }).forEach(
    ([key, value]) => {
      if (value) params.append(key, value);
    }
  );
  return params;
};

const fetchLogs = async () => {
  isLoading.value = true;
  error.value = '';
  try {
    const response = await fetch(
      `/super_admin/ai_agent_tool_executions.json?${buildQueryParams()}`,
      { headers: { 'X-CSRF-Token': csrfToken() } }
    );
    if (!response.ok) throw new Error('Failed to load tool logs.');
    const data = await response.json();
    rows.value = data.payload || [];
    filters.value = data.meta?.filters || filters.value;
  } catch (fetchError) {
    error.value = fetchError.message;
  } finally {
    isLoading.value = false;
  }
};

const updateFilters = nextFilters => {
  filters.value = nextFilters;
  fetchLogs();
};

const updateSort = nextSort => {
  sort.value = nextSort;
  fetchLogs();
};
</script>

<template>
  <ToolLogsTable
    :rows="rows"
    :filters="filters"
    :sort="sort"
    :loading="isLoading"
    :error="error"
    :tool-options="componentData.tool_options"
    :account-options="componentData.account_options"
    show-account-column
    @update:filters="updateFilters"
    @update:sort="updateSort"
    @refresh="fetchLogs"
  />
</template>
