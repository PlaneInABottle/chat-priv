<script setup>
defineProps({
  items: { type: Array, required: true },
  selectedKey: { type: String, required: true },
});

const emit = defineEmits(['select']);
</script>

<template>
  <nav
    class="min-w-0 flex-col overflow-y-auto overscroll-contain border-r border-n-weak pr-4"
  >
    <button
      v-for="item in items"
      :key="item.key"
      type="button"
      class="flex min-h-12 w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm transition-colors hover:bg-n-alpha-black1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      :class="
        selectedKey === item.key
          ? 'bg-n-alpha-black2 font-medium text-n-slate-12'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
      :aria-current="selectedKey === item.key ? 'page' : undefined"
      @click="emit('select', item.key)"
    >
      <span
        aria-hidden="true"
        class="size-4 flex-shrink-0"
        :class="
          item.icon ||
          (item.configured
            ? 'i-lucide-circle-check text-n-teal-10'
            : 'i-lucide-circle text-n-slate-8')
        "
      />
      <span class="flex min-w-0 flex-col">
        <span class="break-words leading-5">{{ item.shortTitle }}</span>
        <span class="break-words text-xs font-normal text-n-slate-9">
          {{ item.statusLabel }}
        </span>
      </span>
    </button>
  </nav>
</template>
