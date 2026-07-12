<script setup>
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const props = defineProps({
  tabs: { type: Array, required: true },
  activeTabIndex: { type: Number, required: true },
  ariaLabel: { type: String, required: true },
});

const emit = defineEmits(['tabChanged']);

const selectMobileTab = event => {
  const selectedTab = props.tabs[Number(event.target.value)];
  if (selectedTab) emit('tabChanged', selectedTab);
};
</script>

<template>
  <div class="min-w-0">
    <div class="sm:hidden">
      <select
        :value="activeTabIndex"
        :aria-label="ariaLabel"
        class="h-10 w-full rounded-lg border-0 bg-n-alpha-1 px-3 text-sm font-medium text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
        @change="selectMobileTab"
      >
        <option v-for="(tab, index) in tabs" :key="tab.value" :value="index">
          {{ tab.label }}
        </option>
      </select>
    </div>
    <TabBar
      class="hidden sm:flex"
      :tabs="tabs"
      :initial-active-tab="activeTabIndex"
      @tab-changed="emit('tabChanged', $event)"
    />
  </div>
</template>
