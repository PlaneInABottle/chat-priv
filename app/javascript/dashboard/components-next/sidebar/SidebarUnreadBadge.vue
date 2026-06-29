<script setup>
import Badge from 'dashboard/components-next/badge/Badge.vue';

defineProps({
  count: {
    type: [Number, String],
    default: 0,
  },
});
</script>

<template>
  <Badge
    data-test-id="sidebar-unread-badge"
    :count="count"
    variant="slate"
    size="md"
    :overflow-threshold="99"
  />
</template>
