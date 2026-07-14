<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

defineProps({
  showProgress: { type: Boolean, default: false },
  currentStep: { type: Number, default: 0 },
  totalSteps: { type: Number, default: 0 },
  progressLabel: { type: String, default: '' },
  primaryLabel: { type: String, required: true },
  backLabel: { type: String, required: true },
  showBack: { type: Boolean, default: false },
  isLoading: { type: Boolean, default: false },
});

defineEmits(['back']);

const { t } = useI18n();
</script>

<template>
  <div class="flex min-h-dvh flex-col bg-n-surface-1 text-body-main">
    <header class="border-b border-n-weak">
      <div class="mx-auto flex h-16 w-full max-w-xl items-center px-5 sm:px-0">
        <div class="flex min-w-0 items-center gap-2.5">
          <span
            class="flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-slate-12 text-n-slate-1"
          >
            <Icon icon="i-lucide-bot" class="size-4" />
          </span>
          <span class="truncate text-sm font-medium text-n-slate-12">
            {{ t('ONBOARDING_NEXT.APP_LABEL') }}
          </span>
        </div>
      </div>
    </header>

    <main class="flex flex-1 justify-center px-5 py-8 sm:px-8 sm:py-14">
      <div class="w-full max-w-xl">
        <div v-if="showProgress" class="mb-8 sm:mb-10">
          <div class="mb-2">
            <span class="text-xs font-medium text-n-slate-10">
              {{ progressLabel }}
            </span>
          </div>
          <div
            class="grid grid-flow-col gap-1.5"
            role="progressbar"
            :aria-label="progressLabel"
            :aria-valuemin="1"
            :aria-valuemax="totalSteps"
            :aria-valuenow="currentStep"
          >
            <span
              v-for="step in totalSteps"
              :key="step"
              class="h-1 rounded-full transition-colors duration-200"
              :class="step <= currentStep ? 'bg-n-brand' : 'bg-n-alpha-2'"
              aria-hidden="true"
            />
          </div>
        </div>

        <slot />

        <footer
          class="mt-8 flex items-center border-t border-n-weak pt-5 sm:mt-10"
          :class="showBack ? 'justify-between' : 'justify-end'"
        >
          <NextButton
            v-if="showBack"
            type="button"
            variant="ghost"
            color="slate"
            icon="i-lucide-arrow-left"
            :label="backLabel"
            data-testid="onboarding-back"
            @click="$emit('back')"
          />
          <NextButton
            type="submit"
            icon="i-lucide-arrow-right"
            :label="primaryLabel"
            :is-loading="isLoading"
            :disabled="isLoading"
            data-testid="onboarding-primary"
          />
        </footer>
      </div>
    </main>
  </div>
</template>
