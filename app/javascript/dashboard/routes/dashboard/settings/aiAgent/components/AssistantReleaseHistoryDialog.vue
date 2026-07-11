<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import AiAgentAPI from 'dashboard/api/aiAgent';
import VoiceAPI from 'dashboard/api/voice';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  assistantType: {
    type: String,
    required: true,
    validator: value => ['text', 'voice'].includes(value),
  },
  assistantId: { type: Number, required: true },
  currentReleaseId: { type: Number, default: null },
});

const emit = defineEmits(['restored']);
const { t } = useI18n();
const dialogRef = ref(null);
const releases = ref([]);
const selectedRelease = ref(null);
const pendingRollback = ref(null);
const isLoading = ref(false);
const isRestoring = ref(false);

const api = computed(() =>
  props.assistantType === 'voice'
    ? {
        list: () => VoiceAPI.getAgentReleases(props.assistantId),
        show: releaseId =>
          VoiceAPI.getAgentRelease(props.assistantId, releaseId),
        rollback: releaseId =>
          VoiceAPI.rollbackAgentRelease(props.assistantId, releaseId),
      }
    : {
        list: () => AiAgentAPI.getReleases(props.assistantId),
        show: releaseId => AiAgentAPI.getRelease(props.assistantId, releaseId),
        rollback: releaseId =>
          AiAgentAPI.rollbackRelease(props.assistantId, releaseId),
      }
);

const formatDate = value =>
  new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));

const sourceLabel = source => {
  if (source === 'publish') {
    return t('AI_ASSISTANT.RELEASE_HISTORY.SOURCE.PUBLISHED');
  }
  if (source === 'rollback') {
    return t('AI_ASSISTANT.RELEASE_HISTORY.SOURCE.RESTORED');
  }
  if (source === 'migration') {
    return t('AI_ASSISTANT.RELEASE_HISTORY.SOURCE.IMPORTED');
  }

  return t('AI_ASSISTANT.RELEASE_HISTORY.SOURCE.UNKNOWN');
};

const releaseMetadata = release => {
  const date = formatDate(release.created_at);
  if (!release.created_by?.name) return date;

  return t('AI_ASSISTANT.RELEASE_HISTORY.CREATED_BY', {
    date,
    name: release.created_by.name,
  });
};

const releasePrompt = computed(() => {
  const snapshot = selectedRelease.value?.snapshot || {};
  return snapshot.prompt || snapshot.greeting || '';
});

const open = async () => {
  isLoading.value = true;
  selectedRelease.value = null;
  pendingRollback.value = null;
  await dialogRef.value?.open();
  try {
    const response = await api.value.list();
    releases.value = response.data || [];
  } catch {
    useAlert(t('AI_ASSISTANT.RELEASE_HISTORY.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const inspectRelease = async release => {
  try {
    const response = await api.value.show(release.id);
    selectedRelease.value = response.data;
    pendingRollback.value = null;
  } catch {
    useAlert(t('AI_ASSISTANT.RELEASE_HISTORY.LOAD_ERROR'));
  }
};

const requestRollback = release => {
  pendingRollback.value = release;
  selectedRelease.value = null;
};

const confirmRollback = async () => {
  if (!pendingRollback.value) return;
  isRestoring.value = true;
  try {
    await api.value.rollback(pendingRollback.value.id);
    useAlert(t('AI_ASSISTANT.RELEASE_HISTORY.RESTORED'));
    emit('restored');
    dialogRef.value?.close();
  } catch {
    useAlert(t('AI_ASSISTANT.RELEASE_HISTORY.RESTORE_ERROR'));
  } finally {
    isRestoring.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :title="t('AI_ASSISTANT.RELEASE_HISTORY.TITLE')"
    :show-confirm-button="Boolean(pendingRollback)"
    :confirm-button-label="t('AI_ASSISTANT.RELEASE_HISTORY.CONFIRM_RESTORE')"
    :is-loading="isRestoring"
    @confirm="confirmRollback"
  >
    <div v-if="isLoading" class="py-10 text-center text-sm text-n-slate-11">
      {{ t('AI_ASSISTANT.RELEASE_HISTORY.LOADING') }}
    </div>
    <div
      v-else-if="!releases.length"
      class="py-10 text-center text-sm text-n-slate-11"
    >
      {{ t('AI_ASSISTANT.RELEASE_HISTORY.EMPTY') }}
    </div>
    <div v-else class="flex min-w-0 flex-col gap-2">
      <div
        v-for="release in releases"
        :key="release.id"
        class="grid min-w-0 grid-cols-[minmax(0,1fr)_auto] gap-3 border-b border-n-weak py-3 last:border-b-0"
      >
        <button
          type="button"
          class="min-w-0 text-left"
          @click="inspectRelease(release)"
        >
          <span class="flex flex-wrap items-center gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{
                t('AI_ASSISTANT.RELEASE_HISTORY.VERSION', {
                  version: release.revision,
                })
              }}
            </span>
            <span
              v-if="release.id === currentReleaseId"
              class="rounded-md bg-n-teal-3 px-2 py-0.5 text-xs font-medium text-n-teal-11"
            >
              {{ t('AI_ASSISTANT.RELEASE_HISTORY.LIVE') }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{ sourceLabel(release.source) }}
            </span>
          </span>
          <span class="mt-1 block text-xs text-n-slate-11">
            {{ releaseMetadata(release) }}
          </span>
        </button>
        <Button
          v-if="release.id !== currentReleaseId"
          icon="i-lucide-rotate-ccw"
          size="sm"
          variant="ghost"
          color="slate"
          :label="t('AI_ASSISTANT.RELEASE_HISTORY.RESTORE')"
          @click="requestRollback(release)"
        />
      </div>
    </div>

    <div
      v-if="selectedRelease"
      class="mt-4 max-h-64 overflow-y-auto border-t border-n-weak pt-4"
    >
      <h4 class="m-0 text-sm font-medium text-n-slate-12">
        {{
          t('AI_ASSISTANT.RELEASE_HISTORY.VERSION', {
            version: selectedRelease.revision,
          })
        }}
      </h4>
      <div
        class="mb-0 mt-2 whitespace-pre-wrap break-words rounded-lg bg-n-alpha-2 p-3 text-xs leading-5 text-n-slate-11"
      >
        {{ releasePrompt }}
      </div>
    </div>

    <p
      v-if="pendingRollback"
      class="mb-0 mt-4 rounded-lg border border-n-amber-5 bg-n-amber-2 p-3 text-sm text-n-amber-11"
    >
      {{
        t('AI_ASSISTANT.RELEASE_HISTORY.RESTORE_WARNING', {
          version: pendingRollback.revision,
        })
      }}
    </p>
  </Dialog>
</template>
