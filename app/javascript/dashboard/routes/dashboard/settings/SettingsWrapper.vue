<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';

defineProps({
  keepAlive: {
    type: Boolean,
    default: true,
  },
});

const route = useRoute();
const viewKey = computed(() => {
  if (!route.meta.keepAliveKey) return route.fullPath;

  const resourceId = route.params.id ? `:${route.params.id}` : '';
  return `${route.meta.keepAliveKey}${resourceId}`;
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full m-0 pb-8 pt-4 px-6 overflow-auto bg-n-surface-1"
  >
    <div
      class="flex items-start w-full mx-auto"
      :class="route.meta.wideLayout ? 'max-w-[90rem]' : 'max-w-5xl'"
    >
      <router-view v-slot="{ Component }">
        <keep-alive v-if="keepAlive">
          <component :is="Component" :key="viewKey" />
        </keep-alive>
        <component :is="Component" v-else :key="viewKey" />
      </router-view>
    </div>
  </div>
</template>
