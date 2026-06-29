<script>
import FeaturePlaceholder from './FeaturePlaceholder.vue';
export default {
  components: { FeaturePlaceholder },
  props: {
    message: {
      type: String,
      required: true,
    },
    ctaLabel: {
      type: String,
      default: '',
    },
    ctaLink: {
      type: String,
      default: '',
    },
  },
};
</script>

<template>
  <div class="flex flex-col items-center justify-center h-full">
    <img
      class="m-4 w-32 hidden dark:block"
      src="dashboard/assets/images/no-chat-dark.svg"
      alt="No Chat dark"
    />
    <img
      class="m-4 w-32 block dark:hidden"
      src="dashboard/assets/images/no-chat.svg"
      alt="No Chat"
    />
    <span class="text-sm text-n-slate-12 font-medium text-center">
      {{ message }}
      <br />
    </span>
    <a
      v-if="ctaLabel && ctaLink"
      :href="ctaLink"
      class="mt-4 inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white bg-n-brand rounded-lg hover:opacity-90 transition-opacity"
    >
      {{ ctaLabel }}
    </a>
    <!-- Cmd bar, keyboard shortcuts placeholder -->
    <FeaturePlaceholder />
  </div>
</template>
