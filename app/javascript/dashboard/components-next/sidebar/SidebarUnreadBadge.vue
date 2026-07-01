<script setup>
import { computed } from 'vue';

import Badge from 'dashboard/components-next/badge/Badge.vue';

const props = defineProps({
  count: {
    type: [Number, String],
    default: 0,
  },
});

const hasCount = computed(() => Number(props.count) > 0);
</script>

<template>
  <Badge
    v-if="hasCount"
    data-test-id="sidebar-unread-badge"
    :count="count"
    variant="slate"
    size="md"
    :overflow-threshold="99"
  />
  <span v-else class="hidden" />
</template>
