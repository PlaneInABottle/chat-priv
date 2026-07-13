<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  voiceAgent: { type: Object, default: null },
  isPublishing: { type: Boolean, default: false },
});

const emit = defineEmits(['confirm']);
const { t } = useI18n();
const dialogRef = ref(null);
const startAnswering = ref(false);

const isCurrentlyActive = computed(() => props.voiceAgent?.enabled === true);
const nextRevision = computed(
  () => Number(props.voiceAgent?.published_revision || 0) + 1
);
const inboxes = computed(() => props.voiceAgent?.inbox_settings || []);
const phoneReady = computed(() =>
  props.voiceAgent?.readiness?.checks?.some(
    check => check.key === 'phone' && check.complete
  )
);
const confirmLabel = computed(() =>
  startAnswering.value
    ? t('VOICE_AI.ROLLOUT.PUBLISH_AND_START')
    : t('VOICE_AI.ROLLOUT.PUBLISH_PAUSED')
);

const open = () => {
  startAnswering.value = isCurrentlyActive.value;
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();
const confirm = () => emit('confirm', { activate: startAnswering.value });

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="lg"
    :title="t('VOICE_AI.ROLLOUT.TITLE')"
    :description="
      t('VOICE_AI.ROLLOUT.DESCRIPTION', {
        version: nextRevision,
        name: voiceAgent?.name,
      })
    "
    :confirm-button-label="confirmLabel"
    :is-loading="isPublishing"
    @confirm="confirm"
  >
    <div class="flex min-w-0 flex-col gap-5">
      <section class="border-y border-n-weak py-4">
        <h4 class="m-0 text-sm font-medium text-n-slate-12">
          {{ t('VOICE_AI.ROLLOUT.INBOXES_TITLE') }}
        </h4>
        <ul class="mb-0 mt-3 flex list-none flex-col gap-2 p-0">
          <li
            v-for="inbox in inboxes"
            :key="inbox.id"
            class="flex min-w-0 items-center gap-2 text-sm text-n-slate-12"
          >
            <span
              aria-hidden="true"
              class="i-lucide-inbox size-4 flex-shrink-0 text-n-slate-10"
            />
            <span class="truncate">{{ inbox.inbox_name }}</span>
          </li>
        </ul>
      </section>

      <div class="flex items-start gap-3 text-sm">
        <span
          aria-hidden="true"
          class="mt-0.5 size-4 flex-shrink-0"
          :class="
            phoneReady
              ? 'i-lucide-circle-check text-n-teal-10'
              : 'i-lucide-circle-alert text-n-amber-10'
          "
        />
        <div>
          <p class="m-0 font-medium text-n-slate-12">
            {{
              phoneReady
                ? t('VOICE_AI.ROLLOUT.PHONE_READY')
                : t('VOICE_AI.ROLLOUT.PHONE_MISSING')
            }}
          </p>
          <p v-if="!phoneReady" class="mb-0 mt-1 text-xs text-n-slate-10">
            {{ t('VOICE_AI.ROLLOUT.PHONE_MISSING_HELP') }}
          </p>
        </div>
      </div>

      <div
        v-if="isCurrentlyActive"
        class="border-l-2 border-n-teal-8 pl-3 text-sm text-n-slate-11"
      >
        {{ t('VOICE_AI.ROLLOUT.ACTIVE_UPDATE') }}
      </div>
      <label v-else class="flex items-start justify-between gap-4">
        <span>
          <span class="block text-sm font-medium text-n-slate-12">
            {{ t('VOICE_AI.ROLLOUT.START_ANSWERING') }}
          </span>
          <span class="mt-1 block text-xs text-n-slate-10">
            {{ t('VOICE_AI.ROLLOUT.START_ANSWERING_HELP') }}
          </span>
        </span>
        <Switch
          v-model="startAnswering"
          :aria-label="t('VOICE_AI.ROLLOUT.START_ANSWERING')"
        />
      </label>
    </div>
  </Dialog>
</template>
