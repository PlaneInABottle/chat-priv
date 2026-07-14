<script setup>
import { computed, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

import AiAgentWebsiteImportsAPI from 'dashboard/api/aiAgentWebsiteImports';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ImprovementCreditsSummary from './ImprovementCreditsSummary.vue';

const props = defineProps({
  aiAgentId: { type: Number, required: true },
  defaultWebsite: { type: String, default: '' },
  currentDocument: { type: Object, required: true },
  expectedDraftFingerprint: { type: String, default: '' },
});

const emit = defineEmits(['applied', 'stateChanged']);
const { t } = useI18n();
const { formatMessage } = useMessageFormatter();
const dialog = ref(null);
const websiteUrl = ref('');
const websiteImport = ref(null);
const sectionChoices = ref({});
const attachKnowledge = ref(true);
const isStarting = ref(false);
const isApplying = ref(false);
const isDialogOpen = ref(false);
const improvementCreditsRef = ref(null);
const improvementUsage = ref(null);
const applyErrorCode = ref('');
let pollTimer = null;

const api = computed(() => new AiAgentWebsiteImportsAPI(props.aiAgentId));
const isRunning = computed(
  () =>
    ['pending', 'running'].includes(websiteImport.value?.status) &&
    !websiteImport.value?.stale
);
const isStale = computed(() => Boolean(websiteImport.value?.stale));
const isReady = computed(() => websiteImport.value?.status === 'ready');
const hasReviewContext = computed(() =>
  Boolean(websiteImport.value?.has_review_context)
);
const proposalSections = computed(() => {
  const proposals = websiteImport.value?.proposed_sections || {};
  return Object.keys(proposals).filter(
    key =>
      proposals[key]?.trim() &&
      proposals[key]?.trim() !==
        (props.currentDocument.sections?.[key] || '').trim()
  );
});
const selectedSections = computed(() =>
  proposalSections.value.filter(
    key => sectionChoices.value[key] === 'suggestion'
  )
);
const knowledgeAvailable = computed(() =>
  Boolean(websiteImport.value?.knowledge_available)
);
const creditsExhausted = computed(
  () => improvementUsage.value?.status === 'exhausted'
);
const canApply = computed(
  () =>
    isReady.value &&
    hasReviewContext.value &&
    !applyErrorCode.value &&
    (selectedSections.value.length > 0 ||
      (attachKnowledge.value && knowledgeAvailable.value))
);
const canRestart = computed(
  () =>
    isStale.value ||
    websiteImport.value?.status === 'failed' ||
    applyErrorCode.value === 'draft_changed' ||
    (isReady.value &&
      (!hasReviewContext.value ||
        (!proposalSections.value.length && !knowledgeAvailable.value)))
);

const errorKeys = {
  invalid_website: 'INVALID_WEBSITE',
  ai_improvement_credits_exhausted: 'CREDITS_EXHAUSTED',
  website_import_rate_limited: 'RATE_LIMITED',
  timed_out: 'TIMED_OUT',
  website_too_large: 'TOO_LARGE',
  website_unreachable: 'UNREACHABLE',
  generation_failed: 'GENERATION_FAILED',
  analysis_failed: 'ANALYSIS_FAILED',
  draft_changed: 'DRAFT_CHANGED',
  knowledge_source_limit: 'KNOWLEDGE_SOURCE_LIMIT',
  invalid_selection: 'INVALID_SELECTION',
};

const localizedError = (code, fallback) => {
  const key = errorKeys[code];
  return key ? t(`AI_ASSISTANT.WEBSITE_IMPORT.ERROR.${key}`) : t(fallback);
};

const failureMessage = computed(() =>
  localizedError(
    websiteImport.value?.error_code,
    'AI_ASSISTANT.WEBSITE_IMPORT.ERROR.START'
  )
);

const sourceLabel = sourceUrl => {
  try {
    const parsedUrl = new URL(sourceUrl);
    const path = parsedUrl.pathname.replace(/\/$/, '');
    return `${parsedUrl.hostname}${path}`;
  } catch {
    return sourceUrl;
  }
};

const sectionLabel = key =>
  t(`AI_ASSISTANT.INSTRUCTIONS.SECTIONS.${key.toUpperCase()}.TITLE`);

const formattedSection = value =>
  formatMessage(value || '', false, false, false);

const sectionWasEdited = key =>
  (websiteImport.value?.base_document?.sections?.[key] || '').trim() !==
  (props.currentDocument.sections?.[key] || '').trim();

const initializeReview = data => {
  websiteImport.value = data;
  applyErrorCode.value = '';
  const choices = {};
  const proposals = data?.proposed_sections || {};
  Object.keys(proposals).forEach(key => {
    if (!proposals[key]?.trim()) return;
    choices[key] = sectionWasEdited(key) ? 'current' : 'suggestion';
  });
  sectionChoices.value = choices;
  attachKnowledge.value = Boolean(data?.knowledge_available);
};

const stopPolling = () => {
  if (pollTimer) clearTimeout(pollTimer);
  pollTimer = null;
};

const refreshImprovementUsage = () => improvementCreditsRef.value?.refresh();

const pollImport = async () => {
  try {
    const { data } = await api.value.show(websiteImport.value.id);
    initializeReview(data);
    emit('stateChanged', data);
    stopPolling();
    if (['pending', 'running'].includes(data.status) && !data.stale) {
      pollTimer = setTimeout(pollImport, 1500);
    } else {
      await refreshImprovementUsage();
    }
  } catch {
    stopPolling();
    pollTimer = setTimeout(pollImport, 3000);
  }
};

const restartImport = async () => {
  stopPolling();
  if (isReady.value) {
    try {
      await api.value.dismiss(websiteImport.value.id);
    } catch {
      useAlert(t('AI_ASSISTANT.WEBSITE_IMPORT.ERROR.RESTART'));
      return;
    }
  }
  websiteImport.value = null;
  sectionChoices.value = {};
  applyErrorCode.value = '';
  emit('stateChanged', null);
};

const startImport = async () => {
  if (!websiteUrl.value.trim() || creditsExhausted.value) return;

  isStarting.value = true;
  try {
    const { data } = await api.value.create({
      website_url: websiteUrl.value.trim(),
    });
    initializeReview(data);
    emit('stateChanged', data);
    if (['pending', 'running'].includes(data.status)) {
      pollTimer = setTimeout(pollImport, 1000);
    }
  } catch (error) {
    await refreshImprovementUsage();
    useAlert(
      localizedError(
        error.response?.data?.code,
        'AI_ASSISTANT.WEBSITE_IMPORT.ERROR.START'
      )
    );
  } finally {
    isStarting.value = false;
  }
};

const applyImport = async () => {
  if (!canApply.value) return;

  isApplying.value = true;
  try {
    const { data } = await api.value.applyImport(websiteImport.value.id, {
      section_keys: selectedSections.value,
      current_document: props.currentDocument,
      attach_knowledge: attachKnowledge.value,
      expected_draft_fingerprint: props.expectedDraftFingerprint,
    });
    emit('applied');
    emit('stateChanged', data);
    dialog.value.close();
    useAlert(t('AI_ASSISTANT.WEBSITE_IMPORT.APPLIED'));
  } catch (error) {
    const errorCode = error.response?.data?.code || '';
    applyErrorCode.value = errorCode === 'draft_changed' ? errorCode : '';
    useAlert(
      localizedError(errorCode, 'AI_ASSISTANT.WEBSITE_IMPORT.ERROR.APPLY')
    );
  } finally {
    isApplying.value = false;
  }
};

const open = async () => {
  isDialogOpen.value = true;
  websiteUrl.value = props.defaultWebsite;
  websiteImport.value = null;
  sectionChoices.value = {};
  applyErrorCode.value = '';
  dialog.value.open();
  await refreshImprovementUsage();

  try {
    const { data } = await api.value.get();
    if (!isDialogOpen.value) return;

    const latest = data[0];
    if (
      !latest ||
      !['pending', 'running', 'ready', 'failed'].includes(latest.status)
    ) {
      return;
    }

    initializeReview(latest);
    websiteUrl.value = latest.website_url;
    if (['pending', 'running'].includes(latest.status) && !latest.stale) {
      pollTimer = setTimeout(pollImport, 1000);
    }
  } catch {
    useAlert(t('AI_ASSISTANT.WEBSITE_IMPORT.ERROR.LOAD'));
  }
};

const handleClose = () => {
  isDialogOpen.value = false;
  stopPolling();
};

onUnmounted(stopPolling);
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="4xl"
    position="top"
    :title="t('AI_ASSISTANT.WEBSITE_IMPORT.TITLE')"
    :description="t('AI_ASSISTANT.WEBSITE_IMPORT.DESCRIPTION')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="handleClose"
  >
    <div
      class="flex max-h-[70dvh] flex-col gap-5 overflow-y-auto overscroll-contain px-1"
      :class="{ 'min-h-72': isRunning }"
    >
      <ImprovementCreditsSummary
        ref="improvementCreditsRef"
        @loaded="improvementUsage = $event"
      />

      <form
        v-if="!websiteImport"
        class="flex flex-col gap-2 sm:flex-row"
        @submit.prevent="startImport"
      >
        <label
          class="flex min-w-0 flex-1 flex-col gap-1 text-sm font-medium text-n-slate-12"
        >
          {{ t('AI_ASSISTANT.WEBSITE_IMPORT.URL_LABEL') }}
          <input
            v-model="websiteUrl"
            type="text"
            inputmode="url"
            name="website_url"
            autocomplete="url"
            spellcheck="false"
            required
            :placeholder="t('AI_ASSISTANT.WEBSITE_IMPORT.URL_PLACEHOLDER')"
            class="!mb-0 h-10 w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-n-brand"
          />
        </label>
        <Button
          type="submit"
          icon="i-lucide-scan-search"
          class="self-end"
          :label="t('AI_ASSISTANT.WEBSITE_IMPORT.ANALYZE')"
          :is-loading="isStarting"
          :disabled="!websiteUrl.trim() || creditsExhausted"
        />
      </form>

      <div
        v-else-if="isRunning"
        role="status"
        aria-live="polite"
        class="flex flex-1 flex-col items-center justify-center gap-3 py-12 text-center"
      >
        <Spinner :size="24" class="text-n-blue-10" />
        <p class="m-0 text-sm font-medium text-n-slate-12">
          {{
            t(
              `AI_ASSISTANT.WEBSITE_IMPORT.STAGE.${websiteImport.stage.toUpperCase()}`
            )
          }}
        </p>
        <p class="m-0 max-w-md text-sm text-n-slate-10">
          {{ t('AI_ASSISTANT.WEBSITE_IMPORT.PROGRESS_HELP') }}
        </p>
      </div>

      <div
        v-else-if="websiteImport?.status === 'failed' || isStale"
        role="alert"
        class="flex flex-1 flex-col items-center justify-center gap-3 py-12 text-center"
      >
        <Icon icon="i-lucide-circle-alert" class="size-6 text-n-ruby-11" />
        <p class="m-0 max-w-md text-sm text-n-slate-11">
          {{
            isStale
              ? t('AI_ASSISTANT.WEBSITE_IMPORT.ERROR.TIMED_OUT')
              : failureMessage
          }}
        </p>
        <Button
          variant="outline"
          color="slate"
          :label="t('AI_ASSISTANT.WEBSITE_IMPORT.TRY_AGAIN')"
          @click="restartImport"
        />
      </div>

      <template v-else-if="isReady">
        <div
          v-if="applyErrorCode"
          role="alert"
          class="flex items-start gap-3 rounded-lg border border-n-amber-5 bg-n-amber-2 p-3"
        >
          <Icon
            icon="i-lucide-triangle-alert"
            class="mt-0.5 size-4 text-n-amber-11"
          />
          <p class="m-0 text-sm text-n-amber-12">
            {{
              localizedError(
                applyErrorCode,
                'AI_ASSISTANT.WEBSITE_IMPORT.ERROR.APPLY'
              )
            }}
          </p>
        </div>

        <div
          v-if="!hasReviewContext"
          role="alert"
          class="flex items-start gap-3 rounded-lg border border-n-amber-5 bg-n-amber-2 p-3"
        >
          <Icon
            icon="i-lucide-triangle-alert"
            class="mt-0.5 size-4 text-n-amber-11"
          />
          <p class="m-0 text-sm text-n-amber-12">
            {{ t('AI_ASSISTANT.WEBSITE_IMPORT.ERROR.REVIEW_CONTEXT_MISSING') }}
          </p>
        </div>

        <div
          v-else
          class="flex items-start gap-3 rounded-lg border border-n-blue-5 bg-n-blue-2 p-3"
        >
          <Icon icon="i-lucide-info" class="mt-0.5 size-4 text-n-blue-11" />
          <p class="m-0 text-sm text-n-blue-12">
            {{ t('AI_ASSISTANT.WEBSITE_IMPORT.REVIEW_HELP') }}
          </p>
        </div>

        <div v-if="websiteImport.source_urls?.length" class="min-w-0">
          <p class="mb-2 text-xs font-semibold uppercase text-n-slate-10">
            {{ t('AI_ASSISTANT.WEBSITE_IMPORT.SOURCES') }}
          </p>
          <ul class="m-0 flex list-none flex-wrap gap-2 p-0">
            <li v-for="sourceUrl in websiteImport.source_urls" :key="sourceUrl">
              <a
                :href="sourceUrl"
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex max-w-full items-center gap-1 break-all text-sm text-n-blue-11 underline"
              >
                <Icon
                  icon="i-lucide-external-link"
                  class="size-3.5 flex-shrink-0"
                />
                {{ sourceLabel(sourceUrl) }}
              </a>
            </li>
          </ul>
        </div>

        <div
          v-for="key in proposalSections"
          :key="key"
          class="border-b border-n-weak py-5 last:border-b-0"
        >
          <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
            <div>
              <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                {{ sectionLabel(key) }}
              </h3>
              <p
                v-if="sectionWasEdited(key)"
                class="mb-0 mt-1 text-xs text-n-amber-11"
              >
                {{ t('AI_ASSISTANT.WEBSITE_IMPORT.EDITED_SINCE_ANALYSIS') }}
              </p>
            </div>
            <div class="grid grid-cols-2 rounded-md bg-n-alpha-black2 p-1">
              <button
                type="button"
                class="h-8 rounded px-3 text-xs font-medium"
                :class="
                  sectionChoices[key] === 'current'
                    ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                    : 'text-n-slate-10'
                "
                @click="sectionChoices[key] = 'current'"
              >
                {{ t('AI_ASSISTANT.WEBSITE_IMPORT.KEEP_CURRENT') }}
              </button>
              <button
                type="button"
                class="h-8 rounded px-3 text-xs font-medium"
                :class="
                  sectionChoices[key] === 'suggestion'
                    ? 'bg-n-solid-1 text-n-teal-11 shadow-sm'
                    : 'text-n-slate-10'
                "
                @click="sectionChoices[key] = 'suggestion'"
              >
                {{ t('AI_ASSISTANT.WEBSITE_IMPORT.USE_SUGGESTION') }}
              </button>
            </div>
          </div>

          <div class="grid gap-4 md:grid-cols-2">
            <div class="min-w-0">
              <p class="mb-2 text-xs font-semibold uppercase text-n-slate-10">
                {{ t('AI_ASSISTANT.WEBSITE_IMPORT.CURRENT') }}
              </p>
              <div
                v-if="currentDocument.sections[key]"
                v-dompurify-html="
                  formattedSection(currentDocument.sections[key])
                "
                class="prose prose-sm m-0 max-w-none break-words text-n-slate-11 dark:prose-invert prose-p:my-0 prose-ul:my-0 prose-li:my-1"
              />
              <p v-else class="m-0 text-sm leading-6 text-n-slate-10">
                {{ t('AI_ASSISTANT.WEBSITE_IMPORT.EMPTY') }}
              </p>
            </div>
            <div class="min-w-0 md:border-l md:border-n-weak md:pl-4">
              <p class="mb-2 text-xs font-semibold uppercase text-n-teal-11">
                {{ t('AI_ASSISTANT.WEBSITE_IMPORT.SUGGESTED') }}
              </p>
              <div
                v-dompurify-html="
                  formattedSection(websiteImport.proposed_sections[key])
                "
                class="prose prose-sm m-0 max-w-none break-words text-n-slate-12 dark:prose-invert prose-p:my-0 prose-ul:my-0 prose-li:my-1"
              />
            </div>
          </div>
        </div>

        <p
          v-if="!proposalSections.length"
          class="py-4 text-center text-sm text-n-slate-10"
        >
          {{ t('AI_ASSISTANT.WEBSITE_IMPORT.NO_CHANGES') }}
        </p>

        <label
          v-if="knowledgeAvailable"
          class="flex cursor-pointer items-start gap-3 border-t border-n-weak pt-5"
        >
          <input
            v-model="attachKnowledge"
            type="checkbox"
            class="mt-1 size-4 rounded border-n-weak text-n-brand"
          />
          <span class="min-w-0">
            <span class="block text-sm font-medium text-n-slate-12">
              {{ t('AI_ASSISTANT.WEBSITE_IMPORT.ATTACH_KNOWLEDGE') }}
            </span>
            <span class="mt-1 block text-xs leading-5 text-n-slate-10">
              {{
                t('AI_ASSISTANT.WEBSITE_IMPORT.ATTACH_KNOWLEDGE_HELP', {
                  pages: websiteImport.source_count,
                  characters: websiteImport.knowledge_character_count,
                })
              }}
            </span>
          </span>
        </label>
      </template>
    </div>

    <template #footer>
      <div class="flex w-full flex-wrap justify-end gap-2">
        <Button
          variant="ghost"
          color="slate"
          :label="t('AI_ASSISTANT.WEBSITE_IMPORT.CANCEL')"
          @click="dialog.close()"
        />
        <Button
          v-if="canRestart"
          icon="i-lucide-rotate-ccw"
          variant="outline"
          color="slate"
          :label="t('AI_ASSISTANT.WEBSITE_IMPORT.START_OVER')"
          @click="restartImport"
        />
        <Button
          v-if="isReady && hasReviewContext"
          icon="i-lucide-check"
          :label="t('AI_ASSISTANT.WEBSITE_IMPORT.APPLY_SELECTED')"
          :disabled="!canApply"
          :is-loading="isApplying"
          @click="applyImport"
        />
      </div>
    </template>
  </Dialog>
</template>
