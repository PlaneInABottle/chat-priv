<script setup>
defineProps({
  count: {
    type: Number,
    default: 5,
  },
  variant: {
    type: String,
    default: 'conversation',
    validator: v => ['conversation', 'contact', 'generic'].includes(v),
  },
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      v-for="i in count"
      :key="i"
      class="flex items-center gap-3 px-3 py-4 animate-pulse"
    >
      <div
        class="flex-shrink-0 rounded-full bg-n-slate-3 dark:bg-n-slate-4"
        :class="variant === 'conversation' ? 'size-6' : 'size-10'"
      />
      <div class="flex flex-col flex-1 gap-2">
        <div class="h-3 rounded bg-n-slate-3 dark:bg-n-slate-4 w-1/3" />
        <div class="h-2.5 rounded bg-n-slate-2 dark:bg-n-slate-3 w-2/3" />
      </div>
      <div
        class="flex-shrink-0 h-2.5 w-12 rounded bg-n-slate-2 dark:bg-n-slate-3"
      />
    </div>
  </div>
</template>
