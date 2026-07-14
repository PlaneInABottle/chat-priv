<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import AiAgentWebsiteImportsAPI from 'dashboard/api/aiAgentWebsiteImports';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import WebsiteImportDialog from './WebsiteImportDialog.vue';

const props = defineProps({
  aiAgentId: { type: Number, required: true },
  defaultWebsite: { type: String, default: '' },
  currentDocument: { type: Object, required: true },
  expectedDraftFingerprint: { type: String, default: '' },
});

const emit = defineEmits(['applied', 'readyCountChanged']);
const { t } = useI18n();
const latestImport = ref(null);
const dialog = ref(null);
const didAnnounceReady = ref(false);
let pollTimer = null;
let isMounted = false;
let loadSequence = 0;

const api = computed(() => new AiAgentWebsiteImportsAPI(props.aiAgentId));
const isRunning = computed(
  () =>
    ['pending', 'running'].includes(latestImport.value?.status) &&
    !latestImport.value?.stale
);
const isReady = computed(() => latestImport.value?.status === 'ready');
const isFailed = computed(
  () => latestImport.value?.status === 'failed' || latestImport.value?.stale
);
const knowledgeAvailable = computed(() =>
  Boolean(latestImport.value?.knowledge_available)
);
const readyCount = computed(() => {
  if (!isReady.value) return 0;

  const proposals = latestImport.value?.proposed_sections || {};
  return Object.keys(proposals).filter(
    key =>
      proposals[key]?.trim() &&
      proposals[key].trim() !==
        (props.currentDocument.sections?.[key] || '').trim()
  ).length;
});
const readyTitle = computed(() => {
  if (readyCount.value) {
    return t('AI_ASSISTANT.WEBSITE_IMPORT.READY_TITLE', {
      count: readyCount.value,
    });
  }
  return knowledgeAvailable.value
    ? t('AI_ASSISTANT.WEBSITE_IMPORT.READY_KNOWLEDGE_TITLE')
    : t('AI_ASSISTANT.WEBSITE_IMPORT.READY_NO_CHANGES_TITLE');
});
const readyHelp = computed(() =>
  readyCount.value || knowledgeAvailable.value
    ? t('AI_ASSISTANT.WEBSITE_IMPORT.STATUS_READY_HELP', {
        pages: latestImport.value?.source_count,
      })
    : t('AI_ASSISTANT.WEBSITE_IMPORT.STATUS_READY_NO_CHANGES_HELP')
);

const hostname = computed(() => {
  try {
    return new URL(latestImport.value?.website_url).hostname;
  } catch {
    return latestImport.value?.website_url || props.defaultWebsite;
  }
});

const stopPolling = () => {
  if (pollTimer) clearTimeout(pollTimer);
  pollTimer = null;
};

const setImport = value => {
  latestImport.value = value;
  if (!isReady.value) didAnnounceReady.value = false;
  if (
    isReady.value &&
    (readyCount.value || knowledgeAvailable.value) &&
    !didAnnounceReady.value
  ) {
    didAnnounceReady.value = true;
    useAlert(t('AI_ASSISTANT.WEBSITE_IMPORT.READY_TO_REVIEW'));
  }
};

const loadLatest = async () => {
  if (!isMounted) return;

  const requestedAgentId = props.aiAgentId;
  loadSequence += 1;
  const requestSequence = loadSequence;
  const requestApi = api.value;

  try {
    const { data } = await requestApi.get();
    if (
      !isMounted ||
      requestedAgentId !== props.aiAgentId ||
      requestSequence !== loadSequence
    ) {
      return;
    }

    const candidate = data[0];
    const latest =
      candidate &&
      ['pending', 'running', 'ready', 'failed'].includes(candidate.status)
        ? candidate
        : null;
    setImport(latest || null);
    stopPolling();
    if (
      latest &&
      ['pending', 'running'].includes(latest.status) &&
      !latest.stale
    ) {
      pollTimer = setTimeout(loadLatest, 1500);
    }
  } catch {
    if (
      !isMounted ||
      requestedAgentId !== props.aiAgentId ||
      requestSequence !== loadSequence
    ) {
      return;
    }

    stopPolling();
    pollTimer = setTimeout(loadLatest, 3000);
  }
};

const handleStateChanged = value => {
  const activeValue =
    value && ['pending', 'running', 'ready', 'failed'].includes(value.status)
      ? value
      : null;
  setImport(activeValue);
  if (
    activeValue &&
    ['pending', 'running'].includes(activeValue.status) &&
    !activeValue.stale
  ) {
    stopPolling();
    pollTimer = setTimeout(loadLatest, 1500);
  }
};

const dismissReady = async () => {
  if (!isReady.value) return;
  try {
    await api.value.dismiss(latestImport.value.id);
    if (!isMounted) return;

    setImport(null);
  } catch {
    if (!isMounted) return;

    useAlert(t('AI_ASSISTANT.WEBSITE_IMPORT.ERROR.DISMISS'));
  }
};

const handleApplied = () => {
  setImport(null);
  emit('applied');
};

onMounted(() => {
  isMounted = true;
  loadLatest();
});
onUnmounted(() => {
  isMounted = false;
  loadSequence += 1;
  stopPolling();
});
watch(
  () => props.aiAgentId,
  () => {
    loadSequence += 1;
    stopPolling();
    didAnnounceReady.value = false;
    setImport(null);
    if (isMounted) loadLatest();
  }
);
watch(readyCount, value => emit('readyCountChanged', value), {
  immediate: true,
});
</script>

<template>
  <div
    class="flex flex-col gap-3 border-y border-n-weak py-3 sm:flex-row sm:items-center sm:justify-between"
    :class="isReady ? 'bg-n-teal-2 px-3' : ''"
  >
    <div class="flex min-w-0 items-start gap-3">
      <Spinner v-if="isRunning" :size="18" class="mt-0.5 text-n-blue-10" />
      <Icon
        v-else
        :icon="
          isReady
            ? 'i-lucide-circle-check'
            : isFailed
              ? 'i-lucide-circle-alert'
              : 'i-lucide-globe-2'
        "
        class="mt-0.5 size-4 flex-shrink-0"
        :class="
          isReady
            ? 'text-n-teal-11'
            : isFailed
              ? 'text-n-amber-11'
              : 'text-n-slate-10'
        "
      />
      <div class="min-w-0">
        <p class="m-0 text-sm font-medium text-n-slate-12">
          <template v-if="isRunning">
            {{
              t(
                `AI_ASSISTANT.WEBSITE_IMPORT.STAGE.${latestImport.stage.toUpperCase()}`
              )
            }}
          </template>
          <template v-else-if="isReady">
            {{ readyTitle }}
          </template>
          <template v-else-if="isFailed">
            {{ t('AI_ASSISTANT.WEBSITE_IMPORT.FAILED_TITLE') }}
          </template>
          <template v-else>
            {{ t('AI_ASSISTANT.WEBSITE_IMPORT.ENTRY_TITLE') }}
          </template>
        </p>
        <p class="mb-0 mt-1 break-words text-xs text-n-slate-10">
          <template v-if="isRunning">
            {{
              t('AI_ASSISTANT.WEBSITE_IMPORT.STATUS_RUNNING_HELP', {
                website: hostname,
              })
            }}
          </template>
          <template v-else-if="isReady">
            {{ readyHelp }}
          </template>
          <template v-else-if="isFailed">
            {{ t('AI_ASSISTANT.WEBSITE_IMPORT.STATUS_FAILED_HELP') }}
          </template>
          <template v-else>
            {{ t('AI_ASSISTANT.WEBSITE_IMPORT.ENTRY_HELP') }}
          </template>
        </p>
      </div>
    </div>

    <div class="flex flex-shrink-0 justify-end gap-2">
      <Button
        v-if="isReady"
        variant="ghost"
        color="slate"
        :label="t('AI_ASSISTANT.WEBSITE_IMPORT.DISMISS')"
        @click="dismissReady"
      />
      <Button
        v-if="!isRunning"
        icon="i-lucide-scan-search"
        :variant="isReady ? 'solid' : 'outline'"
        :color="isReady ? 'blue' : 'slate'"
        :label="
          isReady
            ? readyCount || knowledgeAvailable
              ? t('AI_ASSISTANT.WEBSITE_IMPORT.REVIEW')
              : t('AI_ASSISTANT.WEBSITE_IMPORT.TRY_AGAIN')
            : isFailed
              ? t('AI_ASSISTANT.WEBSITE_IMPORT.TRY_AGAIN')
              : t('AI_ASSISTANT.WEBSITE_IMPORT.ANALYZE')
        "
        @click="dialog.open()"
      />
    </div>

    <WebsiteImportDialog
      ref="dialog"
      :ai-agent-id="aiAgentId"
      :default-website="defaultWebsite"
      :current-document="currentDocument"
      :expected-draft-fingerprint="expectedDraftFingerprint"
      @applied="handleApplied"
      @state-changed="handleStateChanged"
    />
  </div>
</template>
