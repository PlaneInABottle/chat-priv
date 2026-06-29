<script setup>
import Badge from 'dashboard/components-next/badge/Badge.vue';

defineProps({
  count: { type: Number, required: true },
  alignBottom: { type: Boolean, default: false },
});
</script>

<template>
  <span :class="{ 'mb-0.5': alignBottom }">
    <Badge :count="count" variant="teal" size="sm" :overflow-threshold="9" />
  </span>
</template>
