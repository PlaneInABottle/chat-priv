<script setup>
import { computed, ref, onMounted, nextTick, watch } from 'vue';
import { useResizeObserver } from '@vueuse/core';

const props = defineProps({
  initialActiveTab: {
    type: Number,
    default: 0,
  },
  tabs: {
    type: Array,
    required: true,
    validator: value => {
      return value.every(
        tab =>
          typeof tab.label === 'string' &&
          (tab.count ? typeof tab.count === 'number' : true)
      );
    },
  },
});

const emit = defineEmits(['tabChanged']);

const activeTab = computed(() => props.initialActiveTab);

const tabRefs = ref([]);
const indicatorStyle = ref({});
const enableTransition = ref(false);

const activeElement = computed(() => tabRefs.value[activeTab.value]);

const updateIndicator = () => {
  nextTick(() => {
    if (!activeElement.value) return;

    indicatorStyle.value = {
      left: `${activeElement.value.offsetLeft}px`,
      width: `${activeElement.value.offsetWidth}px`,
    };
  });
};

useResizeObserver(activeElement, updateIndicator);

// Watch for prop/tabs changes to update indicator position
watch([() => props.initialActiveTab, () => props.tabs], updateIndicator, {
  immediate: true,
});

onMounted(() => {
  nextTick(() => {
    enableTransition.value = true;
  });
});

const selectTab = index => {
  emit('tabChanged', props.tabs[index]);
};

const focusTab = index => {
  if (!props.tabs.length) return;

  const nextIndex = (index + props.tabs.length) % props.tabs.length;
  selectTab(nextIndex);
  nextTick(() => tabRefs.value[nextIndex]?.focus());
};

const handleKeydown = (event, index) => {
  const keyHandlers = {
    ArrowRight: () => focusTab(index + 1),
    ArrowDown: () => focusTab(index + 1),
    ArrowLeft: () => focusTab(index - 1),
    ArrowUp: () => focusTab(index - 1),
    Home: () => focusTab(0),
    End: () => focusTab(props.tabs.length - 1),
  };
  const handler = keyHandlers[event.key];
  if (!handler) return;

  event.preventDefault();
  handler();
};

const showDivider = index => {
  return (
    // Show dividers after the active tab, but not after the last tab
    (index > activeTab.value && index < props.tabs.length - 1) ||
    // Show dividers before the active tab, but not immediately before it and not before the first tab
    (index < activeTab.value - 1 && index > -1)
  );
};
</script>

<template>
  <div
    role="tablist"
    class="relative flex h-8 max-w-full items-center overflow-x-auto rounded-lg bg-n-alpha-1 transition-all duration-200 ease-out has-[button:active]:scale-[1.01] dark:bg-n-solid-1 sm:w-fit"
  >
    <div
      class="absolute rounded-lg bg-n-solid-active shadow-sm pointer-events-none h-8 outline-1 outline outline-n-container inset-y-0"
      :class="{ 'transition-all duration-300 ease-out': enableTransition }"
      :style="indicatorStyle"
    />

    <template v-for="(tab, index) in tabs" :key="index">
      <button
        :ref="el => (tabRefs[index] = el)"
        type="button"
        role="tab"
        :aria-selected="activeTab === index"
        :tabindex="activeTab === index ? 0 : -1"
        class="relative z-10 flex-none rounded-lg border-0 px-3 py-1.5 text-sm outline-1 outline-transparent transition-all duration-200 ease-out hover:text-n-brand active:scale-[1.02] sm:px-4"
        :class="[
          activeTab === index
            ? 'text-n-blue-11 scale-100'
            : 'text-n-slate-10 scale-[0.98]',
        ]"
        @click="selectTab(index)"
        @keydown="handleKeydown($event, index)"
      >
        {{ tab.label }} {{ tab.count ? `(${tab.count})` : '' }}
      </button>
      <div
        v-if="index < tabs.length - 1"
        class="w-px h-3.5 rounded my-auto transition-colors duration-300 ease-in-out"
        :class="
          showDivider(index)
            ? 'bg-n-strong'
            : 'bg-transparent dark:bg-transparent'
        "
      />
    </template>
  </div>
</template>
