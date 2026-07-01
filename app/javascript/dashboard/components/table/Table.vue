<script setup>
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';

defineProps({
  table: {
    type: Object,
    required: true,
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
</script>

<template>
  <BaseTable :table="table" :fixed="fixed" :type="type" />
</template>
