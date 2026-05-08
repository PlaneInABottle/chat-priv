<script setup>
import { computed, ref } from 'vue';
import { formatDistanceToNow } from 'date-fns';

const props = defineProps({
  rows: { type: Array, default: () => [] },
  filters: { type: Object, default: () => ({}) },
  sort: {
    type: Object,
    default: () => ({ sort: 'created_at', direction: 'desc' }),
  },
  loading: { type: Boolean, default: false },
  error: { type: String, default: '' },
  showAccountColumn: { type: Boolean, default: false },
  toolOptions: { type: Array, default: () => [] },
  accountOptions: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:filters', 'update:sort', 'refresh']);

const expandedRows = ref({});

const columns = computed(() => {
  const baseColumns = [
    { key: 'created_at', label: 'Time', sortable: true },
    { key: 'tool_key', label: 'Tool', sortable: true },
    { key: 'duration_ms', label: 'Duration', sortable: true },
    { key: 'status', label: 'Status', sortable: true },
    { key: 'conversation', label: 'Conversation' },
    { key: 'expand', label: '' },
  ];

  return props.showAccountColumn
    ? [
        { key: 'account_name', label: 'Account', sortable: true },
        ...baseColumns,
      ]
    : baseColumns;
});

const normalizedFilters = computed(() => ({
  status: '',
  tool_key: '',
  date_range: '',
  start_date: '',
  end_date: '',
  account_id: '',
  ...props.filters,
}));

const toolIconMap = {
  human_handoff: 'i-lucide-user-round-plus',
  ikas_lookup_order: 'i-lucide-package-search',
};

const statusClassMap = {
  executed: 'bg-n-teal-3 text-n-teal-11',
  error: 'bg-n-ruby-3 text-n-ruby-11',
  rejected: 'bg-n-slate-3 text-n-slate-11',
};

const updateFilter = (key, value) => {
  emit('update:filters', { ...normalizedFilters.value, [key]: value });
};

const updateSort = column => {
  if (props.sort.sort === column) {
    emit('update:sort', {
      sort: column,
      direction: props.sort.direction === 'asc' ? 'desc' : 'asc',
    });
    return;
  }

  emit('update:sort', { sort: column, direction: 'desc' });
};

const sortIcon = column => {
  if (props.sort.sort !== column) return 'i-lucide-chevrons-up-down';
  return props.sort.direction === 'asc'
    ? 'i-lucide-chevron-up'
    : 'i-lucide-chevron-down';
};

const toggleRow = rowId => {
  expandedRows.value = {
    ...expandedRows.value,
    [rowId]: !expandedRows.value[rowId],
  };
};

const isRowExpanded = rowId => Boolean(expandedRows.value[rowId]);

const prettyJson = value => JSON.stringify(value ?? null, null, 2);

const textInputValue = event => event.target.value;

const durationLabel = duration => {
  if (duration === null || duration === undefined) return '—';
  return `${duration}ms`;
};

const relativeTime = value => {
  if (!value) return '—';
  return formatDistanceToNow(new Date(value), { addSuffix: true });
};

const toolLabel = row => row.tool_name || row.tool_key || 'Unknown tool';

const toolIcon = row => toolIconMap[row.tool_key] || 'i-lucide-braces';

const statusLabel = status => {
  if (!status) return '—';
  return status.charAt(0).toUpperCase() + status.slice(1);
};

const hasCustomDateRange = computed(
  () => normalizedFilters.value.date_range === 'custom'
);

const labels = {
  allStatuses: 'All statuses',
  executed: 'Executed',
  error: 'Error',
  rejected: 'Rejected',
  allTime: 'All time',
  last24Hours: 'Last 24 hours',
  last7Days: 'Last 7 days',
  last30Days: 'Last 30 days',
  custom: 'Custom',
  allTools: 'All tools',
  allAccounts: 'All accounts',
  refresh: 'Refresh',
  loading: 'Loading tool logs...',
  empty: 'No tool executions yet.',
  startDate: 'Start date',
  endDate: 'End date',
  conversation: 'Conversation',
  arguments: 'Arguments',
  result: 'Result',
  expandRow: 'Expand row',
  collapseRow: 'Collapse row',
  emptyValue: '—',
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-wrap gap-3">
      <select
        :value="normalizedFilters.status"
        class="rounded border border-n-weak p-2 text-sm"
        @change="updateFilter('status', textInputValue($event))"
      >
        <option value="">{{ labels.allStatuses }}</option>
        <option value="executed">{{ labels.executed }}</option>
        <option value="error">{{ labels.error }}</option>
        <option value="rejected">{{ labels.rejected }}</option>
      </select>
      <select
        :value="normalizedFilters.date_range"
        class="rounded border border-n-weak p-2 text-sm"
        @change="updateFilter('date_range', textInputValue($event))"
      >
        <option value="">{{ labels.allTime }}</option>
        <option value="24h">{{ labels.last24Hours }}</option>
        <option value="7d">{{ labels.last7Days }}</option>
        <option value="30d">{{ labels.last30Days }}</option>
        <option value="custom">{{ labels.custom }}</option>
      </select>
      <select
        :value="normalizedFilters.tool_key"
        class="rounded border border-n-weak p-2 text-sm"
        @change="updateFilter('tool_key', textInputValue($event))"
      >
        <option value="">{{ labels.allTools }}</option>
        <option v-for="tool in toolOptions" :key="tool.key" :value="tool.key">
          {{ tool.name || tool.key }}
        </option>
      </select>
      <select
        v-if="showAccountColumn"
        :value="normalizedFilters.account_id"
        class="rounded border border-n-weak p-2 text-sm"
        @change="updateFilter('account_id', textInputValue($event))"
      >
        <option value="">{{ labels.allAccounts }}</option>
        <option
          v-for="account in accountOptions"
          :key="account.id"
          :value="account.id"
        >
          {{ account.name }}
        </option>
      </select>
      <input
        v-if="hasCustomDateRange"
        :value="normalizedFilters.start_date"
        type="datetime-local"
        class="rounded border border-n-weak p-2 text-sm"
        :aria-label="labels.startDate"
        @change="updateFilter('start_date', textInputValue($event))"
      />
      <input
        v-if="hasCustomDateRange"
        :value="normalizedFilters.end_date"
        type="datetime-local"
        class="rounded border border-n-weak p-2 text-sm"
        :aria-label="labels.endDate"
        @change="updateFilter('end_date', textInputValue($event))"
      />
      <button
        type="button"
        class="button button--secondary"
        @click="emit('refresh')"
      >
        {{ labels.refresh }}
      </button>
    </div>
    <p v-if="loading" class="text-sm text-n-slate-11">{{ labels.loading }}</p>
    <p v-else-if="error" class="text-sm text-n-ruby-11">{{ error }}</p>
    <p v-else-if="rows.length === 0" class="text-sm text-n-slate-11">
      {{ labels.empty }}
    </p>
    <div v-else class="overflow-x-auto rounded-lg border border-n-weak">
      <table class="w-full text-left">
        <thead class="bg-n-solid-2 border-b border-n-container">
          <tr>
            <th
              v-for="column in columns"
              :key="column.key"
              class="px-4 py-3 text-sm font-medium text-n-slate-12"
            >
              <button
                v-if="column.sortable"
                type="button"
                class="inline-flex items-center gap-1"
                @click="updateSort(column.key)"
              >
                {{ column.label }}
                <i :class="sortIcon(column.key)" class="size-3" />
              </button>
              <span v-else>{{ column.label }}</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-container">
          <template v-for="row in rows" :key="row.id">
            <tr class="hover:bg-n-slate-2">
              <td
                v-if="showAccountColumn"
                class="px-4 py-3 text-sm text-n-slate-12"
              >
                {{ row.account_name || 'Unknown account' }}
              </td>
              <td class="px-4 py-3 text-sm text-n-slate-11">
                {{ relativeTime(row.created_at) }}
              </td>
              <td class="px-4 py-3">
                <div class="flex items-center gap-2 text-sm text-n-slate-12">
                  <i :class="toolIcon(row)" class="size-4 text-n-slate-10" />
                  <span>{{ toolLabel(row) }}</span>
                </div>
              </td>
              <td class="px-4 py-3 text-sm text-n-slate-11">
                {{ durationLabel(row.duration_ms) }}
              </td>
              <td class="px-4 py-3">
                <span
                  class="rounded-full px-2 py-1 text-xs font-medium"
                  :class="statusClassMap[row.status] || statusClassMap.rejected"
                >
                  {{ statusLabel(row.status) }}
                </span>
              </td>
              <td class="px-4 py-3 text-sm">
                <a
                  v-if="row.conversation_url"
                  :href="row.conversation_url"
                  class="text-n-brand underline"
                >
                  {{ labels.conversation }} {{ row.conversation_display_id }}
                </a>
                <span v-else class="text-n-slate-10">
                  {{ labels.emptyValue }}
                </span>
              </td>
              <td class="px-4 py-3">
                <button
                  type="button"
                  class="rounded p-1 text-n-slate-10 hover:bg-n-slate-3 hover:text-n-slate-12"
                  :aria-label="
                    isRowExpanded(row.id)
                      ? labels.collapseRow
                      : labels.expandRow
                  "
                  @click="toggleRow(row.id)"
                >
                  <i
                    :class="
                      isRowExpanded(row.id)
                        ? 'i-lucide-chevron-up'
                        : 'i-lucide-chevron-down'
                    "
                    class="size-4"
                  />
                </button>
              </td>
            </tr>
            <tr v-if="isRowExpanded(row.id)" class="bg-n-slate-1">
              <td :colspan="columns.length" class="px-4 py-4">
                <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
                  <div>
                    <h4
                      class="mb-2 text-xs font-medium uppercase text-n-slate-11"
                    >
                      {{ labels.arguments }}
                    </h4>
                    <pre
                      class="overflow-auto rounded bg-n-alpha-black1 p-3 text-xs"
                    ><code>{{ prettyJson(row.arguments) }}</code></pre>
                  </div>
                  <div>
                    <h4
                      class="mb-2 text-xs font-medium uppercase text-n-slate-11"
                    >
                      {{ labels.result }}
                    </h4>
                    <pre
                      class="overflow-auto rounded bg-n-alpha-black1 p-3 text-xs"
                    ><code>{{ prettyJson(row.result) }}</code></pre>
                  </div>
                </div>
                <p v-if="row.error_message" class="mt-3 text-sm text-n-ruby-11">
                  {{ row.error_message }}
                </p>
              </td>
            </tr>
          </template>
        </tbody>
      </table>
    </div>
  </div>
</template>
