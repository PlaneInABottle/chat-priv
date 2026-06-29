<script setup>
import { computed } from 'vue';
import { FlexRender } from '@tanstack/vue-table';
import SortButton from 'dashboard/components/table/SortButton.vue';

const props = defineProps({
  table: {
    type: Object,
    default: null,
  },
  headers: {
    type: Array,
    default: () => [],
  },
  items: {
    type: Array,
    default: () => [],
  },
  noDataMessage: {
    type: String,
    default: '',
  },
  loading: {
    type: Boolean,
    default: false,
  },
  fixed: {
    type: Boolean,
    default: false,
  },
  type: {
    type: String,
    default: 'relaxed',
  },
});

const hasTanstackTable = computed(() => !!props.table);
const isRelaxed = computed(() => props.type === 'relaxed');
const hasHeaderSlot = computed(() => !!props.headers.length);
const showHeaders = computed(
  () => !hasTanstackTable.value && hasHeaderSlot.value && props.items.length > 0
);
const tanstackHeaderClass = computed(() =>
  isRelaxed.value
    ? 'ltr:first:rounded-bl-lg ltr:first:rounded-tl-lg ltr:last:rounded-br-lg ltr:last:rounded-tr-lg rtl:first:rounded-br-lg rtl:first:rounded-tr-lg rtl:last:rounded-bl-lg rtl:last:rounded-tl-lg'
    : ''
);
</script>

<template>
  <div class="w-full">
    <table
      v-if="hasTanstackTable"
      class="min-w-full"
      :class="{ 'table-fixed': fixed }"
    >
      <thead class="sticky top-0 z-10 bg-n-slate-1">
        <tr
          v-for="headerGroup in table.getHeaderGroups()"
          :key="headerGroup.id"
          class="rounded-xl"
        >
          <th
            v-for="header in headerGroup.headers"
            :key="header.id"
            :style="{ width: `${header.getSize()}px` }"
            class="py-3 px-5 font-medium text-sm text-n-slate-12 text-start"
            :class="tanstackHeaderClass"
            @click="header.column.getCanSort() && header.column.toggleSorting()"
          >
            <div
              v-if="!header.isPlaceholder"
              class="flex place-items-center gap-1"
            >
              <FlexRender
                :render="header.column.columnDef.header"
                :props="header.getContext()"
              />
              <SortButton v-if="header.column.getCanSort()" :header="header" />
            </div>
          </th>
        </tr>
      </thead>

      <tbody class="divide-y divide-n-slate-2">
        <tr v-for="row in table.getRowModel().rows" :key="row.id">
          <td
            v-for="cell in row.getVisibleCells()"
            :key="cell.id"
            :class="isRelaxed ? 'py-4 px-5' : 'py-2 px-5'"
          >
            <FlexRender
              :render="cell.column.columnDef.cell"
              :props="cell.getContext()"
            />
          </td>
        </tr>
      </tbody>
    </table>

    <table v-else class="min-w-full table-auto divide-y divide-n-weak">
      <thead v-if="showHeaders" class="border-t border-n-weak">
        <tr>
          <th
            v-for="(header, index) in headers"
            :key="index"
            class="py-4 ltr:pr-4 rtl:pl-4 text-start text-heading-3 text-n-slate-12 capitalize"
          >
            <slot :name="`header-${index}`" :header="header">
              {{ header }}
            </slot>
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-n-weak text-n-slate-11">
        <template v-if="items.length">
          <slot name="row" :items="items" />
        </template>
        <tr v-else-if="noDataMessage && !loading">
          <td
            :colspan="headers.length || 1"
            class="py-20 text-center text-body-main !text-base text-n-slate-11"
          >
            {{ noDataMessage }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
