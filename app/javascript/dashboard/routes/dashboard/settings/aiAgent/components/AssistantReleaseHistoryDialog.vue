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
const activeRelease = ref(null);
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

const snapshotValue = (snapshot, key) => snapshot?.[key]?.toString() || '';
const knowledgeSources = snapshot => snapshot?.knowledge_sources || [];
const knowledgeSignature = snapshot =>
  JSON.stringify(
    knowledgeSources(snapshot)
      .map(source => [
        source.name || '',
        source.source_type || '',
        source.content || '',
      ])
      .sort((first, second) =>
        JSON.stringify(first).localeCompare(JSON.stringify(second))
      )
  );
const matchingKnowledgeSource = (source, comparisonSources) =>
  comparisonSources.find(item => item.id && item.id === source.id) ||
  comparisonSources.find(item => item.name === source.name);
const knowledgeValue = (snapshot, comparisonSnapshot) => {
  const comparisonSources = knowledgeSources(comparisonSnapshot);
  return knowledgeSources(snapshot)
    .map(source => {
      const comparison = matchingKnowledgeSource(source, comparisonSources);
      const contentChanged =
        comparison &&
        (source.content !== comparison.content ||
          source.source_type !== comparison.source_type);
      return contentChanged
        ? t('AI_ASSISTANT.RELEASE_HISTORY.KNOWLEDGE_CONTENT_CHANGED', {
            name: source.name,
          })
        : source.name;
    })
    .join('\n');
};

const inlineDiff = (value, comparison) => {
  let prefixLength = 0;
  const maxPrefix = Math.min(value.length, comparison.length);
  while (
    prefixLength < maxPrefix &&
    value[prefixLength] === comparison[prefixLength]
  ) {
    prefixLength += 1;
  }

  let suffixLength = 0;
  const maxSuffix = Math.min(
    value.length - prefixLength,
    comparison.length - prefixLength
  );
  while (
    suffixLength < maxSuffix &&
    value[value.length - suffixLength - 1] ===
      comparison[comparison.length - suffixLength - 1]
  ) {
    suffixLength += 1;
  }

  return [
    { text: value.slice(0, prefixLength), changed: false },
    {
      text: value.slice(prefixLength, value.length - suffixLength),
      changed: true,
    },
    {
      text: suffixLength ? value.slice(value.length - suffixLength) : '',
      changed: false,
    },
  ].filter(segment => segment.text);
};

const diffSegments = (value, comparison) => {
  if (!value) return [];

  const lines = value.split('\n');
  const comparisonLines = comparison.split('\n');
  const unchangedLines = new Set(comparisonLines);

  return lines.flatMap((line, index) => {
    const segments = unchangedLines.has(line)
      ? [{ text: line, changed: false }]
      : inlineDiff(line, comparisonLines[index] || '');
    if (index < lines.length - 1) {
      segments.push({ text: '\n', changed: false });
    }
    return segments;
  });
};

const comparisonRows = computed(() => {
  if (!selectedRelease.value || !activeRelease.value) return [];

  const viewed = selectedRelease.value.snapshot || {};
  const live = activeRelease.value.snapshot || {};
  const knowledgeChanged =
    knowledgeSignature(viewed) !== knowledgeSignature(live);
  const viewedKnowledge = knowledgeValue(viewed, live);
  const liveKnowledge = knowledgeValue(live, viewed);
  const fields =
    props.assistantType === 'voice'
      ? [
          [
            'GREETING',
            snapshotValue(viewed, 'greeting'),
            snapshotValue(live, 'greeting'),
          ],
          [
            'INSTRUCTIONS',
            snapshotValue(viewed, 'prompt'),
            snapshotValue(live, 'prompt'),
          ],
          [
            'LANGUAGE',
            snapshotValue(viewed, 'language'),
            snapshotValue(live, 'language'),
          ],
          [
            'VOICE',
            snapshotValue(viewed, 'voice'),
            snapshotValue(live, 'voice'),
          ],
          ['KNOWLEDGE', viewedKnowledge, liveKnowledge, knowledgeChanged],
        ]
      : [
          [
            'INSTRUCTIONS',
            snapshotValue(viewed, 'prompt'),
            snapshotValue(live, 'prompt'),
          ],
          ['KNOWLEDGE', viewedKnowledge, liveKnowledge, knowledgeChanged],
        ];

  return fields
    .filter(
      ([, viewedValue, liveValue, explicitlyChanged]) =>
        explicitlyChanged || viewedValue !== liveValue
    )
    .map(([key, viewedValue, liveValue]) => ({
      key,
      viewedValue,
      liveValue,
      viewedSegments: diffSegments(viewedValue, liveValue),
      liveSegments: diffSegments(liveValue, viewedValue),
    }));
});

const open = async () => {
  isLoading.value = true;
  selectedRelease.value = null;
  activeRelease.value = null;
  pendingRollback.value = null;
  await dialogRef.value?.open();
  try {
    const response = await api.value.list();
    releases.value = response.data || [];
    if (props.currentReleaseId) {
      try {
        const activeResponse = await api.value.show(props.currentReleaseId);
        activeRelease.value = activeResponse.data;
      } catch {
        activeRelease.value = null;
      }
    }
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
      class="mt-4 max-h-[26rem] overflow-y-auto border-t border-n-weak pt-4"
    >
      <h4 class="m-0 text-sm font-medium text-n-slate-12">
        {{
          t('AI_ASSISTANT.RELEASE_HISTORY.VERSION', {
            version: selectedRelease.revision,
          })
        }}
      </h4>
      <template v-if="selectedRelease.id !== currentReleaseId && activeRelease">
        <p class="mb-0 mt-1 text-xs text-n-slate-10">
          {{ t('AI_ASSISTANT.RELEASE_HISTORY.COMPARE_HELP') }}
        </p>
        <div v-if="comparisonRows.length" class="mt-3 flex flex-col gap-4">
          <section v-for="row in comparisonRows" :key="row.key" class="min-w-0">
            <h5 class="m-0 text-xs font-semibold uppercase text-n-slate-10">
              {{ t(`AI_ASSISTANT.RELEASE_HISTORY.FIELDS.${row.key}`) }}
            </h5>
            <div class="mt-2 grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2">
              <div class="min-w-0 border-l-2 border-n-ruby-7 pl-3">
                <p class="m-0 text-xs font-medium text-n-slate-10">
                  {{ t('AI_ASSISTANT.RELEASE_HISTORY.VIEWED') }}
                </p>
                <p
                  class="mb-0 mt-1 whitespace-pre-wrap break-words text-xs leading-5 text-n-slate-12"
                >
                  <template v-if="row.viewedSegments.length">
                    <span
                      v-for="(segment, index) in row.viewedSegments"
                      :key="`${row.key}-viewed-${index}`"
                      :data-diff-changed="segment.changed || undefined"
                      :class="
                        segment.changed
                          ? 'rounded-sm bg-n-ruby-3 px-0.5 text-n-ruby-11 line-through decoration-n-ruby-8'
                          : ''
                      "
                      >{{ segment.text }}</span
                    >
                  </template>
                  <template v-else>
                    {{ t('AI_ASSISTANT.RELEASE_HISTORY.EMPTY_VALUE') }}
                  </template>
                </p>
              </div>
              <div class="min-w-0 border-l-2 border-n-teal-7 pl-3">
                <p class="m-0 text-xs font-medium text-n-slate-10">
                  {{ t('AI_ASSISTANT.RELEASE_HISTORY.CURRENT_LIVE') }}
                </p>
                <p
                  class="mb-0 mt-1 whitespace-pre-wrap break-words text-xs leading-5 text-n-slate-12"
                >
                  <template v-if="row.liveSegments.length">
                    <span
                      v-for="(segment, index) in row.liveSegments"
                      :key="`${row.key}-live-${index}`"
                      :data-diff-changed="segment.changed || undefined"
                      :class="
                        segment.changed
                          ? 'rounded-sm bg-n-teal-3 px-0.5 text-n-teal-11'
                          : ''
                      "
                      >{{ segment.text }}</span
                    >
                  </template>
                  <template v-else>
                    {{ t('AI_ASSISTANT.RELEASE_HISTORY.EMPTY_VALUE') }}
                  </template>
                </p>
              </div>
            </div>
          </section>
        </div>
        <p v-else class="mb-0 mt-3 text-sm text-n-slate-10">
          {{ t('AI_ASSISTANT.RELEASE_HISTORY.NO_DIFFERENCES') }}
        </p>
      </template>
      <div
        v-else
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
