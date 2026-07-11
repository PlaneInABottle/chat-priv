<script setup>
import { computed, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import AiAgentWebsiteImportsAPI from 'dashboard/api/aiAgentWebsiteImports';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ImprovementCreditsSummary from './ImprovementCreditsSummary.vue';

const props = defineProps({
  aiAgentId: { type: Number, required: true },
  defaultWebsite: { type: String, default: '' },
});

const emit = defineEmits(['applied', 'usageChanged']);
const { t } = useI18n();
const dialog = ref(null);
const websiteUrl = ref('');
const websiteImport = ref(null);
const selectedSections = ref([]);
const isStarting = ref(false);
const isApplying = ref(false);
const isDialogOpen = ref(false);
const improvementCreditsRef = ref(null);
const improvementUsage = ref(null);
let pollTimer = null;

const api = computed(() => new AiAgentWebsiteImportsAPI(props.aiAgentId));
const isRunning = computed(() =>
  ['pending', 'running'].includes(websiteImport.value?.status)
);
const isReady = computed(() => websiteImport.value?.status === 'ready');
const changedSections = computed(
  () => websiteImport.value?.changed_sections || []
);
const currentDocument = computed(
  () => websiteImport.value?.current_document || { sections: {} }
);
const hasDraftConflict = computed(() => websiteImport.value?.draft_changed);
const creditsExhausted = computed(
  () => improvementUsage.value?.status === 'exhausted'
);
const canApply = computed(
  () =>
    isReady.value &&
    !hasDraftConflict.value &&
    selectedSections.value.length > 0
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

const stopPolling = () => {
  if (pollTimer) clearTimeout(pollTimer);
  pollTimer = null;
};

const handleImprovementUsageLoaded = usage => {
  improvementUsage.value = usage;
};

const refreshImprovementUsage = () => improvementCreditsRef.value?.refresh();

const pollImport = async () => {
  try {
    const { data } = await api.value.show(websiteImport.value.id);
    websiteImport.value = data;
    if (data.status === 'ready') selectedSections.value = data.changed_sections;

    stopPolling();
    if (['pending', 'running'].includes(data.status)) {
      pollTimer = setTimeout(pollImport, 1500);
    } else {
      await refreshImprovementUsage();
      emit('usageChanged');
    }
  } catch {
    stopPolling();
    pollTimer = setTimeout(pollImport, 3000);
  }
};

const startImport = async () => {
  if (!websiteUrl.value.trim() || creditsExhausted.value) return;

  isStarting.value = true;
  try {
    const { data } = await api.value.create({
      website_url: websiteUrl.value.trim(),
    });
    websiteImport.value = data;
    selectedSections.value =
      data.status === 'ready' ? data.changed_sections : [];
    if (['pending', 'running'].includes(data.status)) {
      pollTimer = setTimeout(pollImport, 1000);
    }
  } catch (error) {
    await refreshImprovementUsage();
    emit('usageChanged');
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

const toggleSection = key => {
  selectedSections.value = selectedSections.value.includes(key)
    ? selectedSections.value.filter(item => item !== key)
    : [...selectedSections.value, key];
};

const applyImport = async () => {
  if (!canApply.value) return;

  isApplying.value = true;
  try {
    await api.value.applyImport(websiteImport.value.id, {
      section_keys: selectedSections.value,
      expected_draft_fingerprint: websiteImport.value.base_draft_fingerprint,
    });
    emit('applied');
    dialog.value.close();
    useAlert(t('AI_ASSISTANT.WEBSITE_IMPORT.APPLIED'));
  } catch (error) {
    useAlert(
      localizedError(
        error.response?.data?.code,
        'AI_ASSISTANT.WEBSITE_IMPORT.ERROR.APPLY'
      )
    );
  } finally {
    isApplying.value = false;
  }
};

const open = async () => {
  isDialogOpen.value = true;
  websiteUrl.value = props.defaultWebsite;
  websiteImport.value = null;
  selectedSections.value = [];
  dialog.value.open();
  await refreshImprovementUsage();

  try {
    const { data } = await api.value.get();
    if (!isDialogOpen.value) return;

    const latest = data[0];
    if (!latest || !['pending', 'running', 'ready'].includes(latest.status)) {
      return;
    }

    websiteImport.value = latest;
    websiteUrl.value = latest.website_url;
    selectedSections.value =
      latest.status === 'ready' ? latest.changed_sections : [];
    if (['pending', 'running'].includes(latest.status)) {
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
    width="3xl"
    position="top"
    :title="t('AI_ASSISTANT.WEBSITE_IMPORT.TITLE')"
    :description="t('AI_ASSISTANT.WEBSITE_IMPORT.DESCRIPTION')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="handleClose"
  >
    <div
      class="flex max-h-[60dvh] min-h-72 flex-col gap-5 overflow-y-auto overscroll-contain pr-1"
    >
      <ImprovementCreditsSummary
        ref="improvementCreditsRef"
        @loaded="handleImprovementUsageLoaded"
      />
      <form
        v-if="!websiteImport"
        class="flex flex-col gap-2 sm:flex-row"
        @submit.prevent="startImport"
      >
        <label class="min-w-0 flex-1 text-sm font-medium text-n-slate-12">
          {{ t('AI_ASSISTANT.WEBSITE_IMPORT.URL_LABEL') }}
          <input
            v-model="websiteUrl"
            type="url"
            name="website_url"
            autocomplete="url"
            spellcheck="false"
            required
            :placeholder="t('AI_ASSISTANT.WEBSITE_IMPORT.URL_PLACEHOLDER')"
            class="mt-1 h-10 w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
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
        v-else-if="websiteImport?.status === 'failed'"
        role="alert"
        class="flex flex-1 flex-col items-center justify-center gap-3 py-12 text-center"
      >
        <Icon
          aria-hidden="true"
          icon="i-lucide-circle-alert"
          class="size-6 text-n-ruby-11"
        />
        <p class="m-0 max-w-md text-sm text-n-slate-11">
          {{ failureMessage }}
        </p>
        <Button
          variant="outline"
          color="slate"
          :label="t('AI_ASSISTANT.WEBSITE_IMPORT.TRY_AGAIN')"
          @click="websiteImport = null"
        />
      </div>

      <template v-else-if="isReady">
        <div
          class="flex items-start gap-3 rounded-lg border border-n-blue-5 bg-n-blue-2 p-3"
        >
          <Icon
            aria-hidden="true"
            icon="i-lucide-info"
            class="mt-0.5 size-4 text-n-blue-11"
          />
          <p class="m-0 text-sm text-n-blue-12">
            {{ t('AI_ASSISTANT.WEBSITE_IMPORT.REVIEW_HELP') }}
          </p>
        </div>

        <div
          v-if="hasDraftConflict"
          role="alert"
          class="flex items-start gap-3 rounded-lg border border-n-amber-5 bg-n-amber-2 p-3"
        >
          <Icon
            aria-hidden="true"
            icon="i-lucide-triangle-alert"
            class="mt-0.5 size-4 text-n-amber-11"
          />
          <p class="m-0 text-sm text-n-amber-12">
            {{ t('AI_ASSISTANT.WEBSITE_IMPORT.ERROR.DRAFT_CHANGED') }}
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
                class="inline-flex max-w-full items-center gap-1 break-all text-sm text-n-blue-11 underline hover:text-n-blue-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              >
                <Icon
                  aria-hidden="true"
                  icon="i-lucide-external-link"
                  class="size-3.5 flex-shrink-0"
                />
                {{ sourceLabel(sourceUrl) }}
              </a>
            </li>
          </ul>
        </div>

        <p
          v-if="!changedSections.length"
          class="py-8 text-center text-sm text-n-slate-10"
        >
          {{ t('AI_ASSISTANT.WEBSITE_IMPORT.NO_CHANGES') }}
        </p>

        <label
          v-for="key in changedSections"
          :key="key"
          class="grid cursor-pointer gap-3 border-b border-n-weak py-4 last:border-b-0 md:grid-cols-[1.25rem_minmax(0,1fr)_minmax(0,1fr)]"
        >
          <input
            type="checkbox"
            class="mt-1 size-4 rounded border-n-weak text-n-brand"
            :checked="selectedSections.includes(key)"
            @change="toggleSection(key)"
          />
          <div class="min-w-0">
            <p
              class="mb-2 flex flex-wrap gap-1 text-xs font-semibold uppercase text-n-slate-10"
            >
              <span>{{ sectionLabel(key) }}</span>
              <span>{{ t('AI_ASSISTANT.WEBSITE_IMPORT.CURRENT') }}</span>
            </p>
            <p
              class="m-0 whitespace-pre-wrap break-words text-sm leading-6 text-n-slate-11"
            >
              {{
                currentDocument.sections[key] ||
                t('AI_ASSISTANT.WEBSITE_IMPORT.EMPTY')
              }}
            </p>
          </div>
          <div class="min-w-0 md:border-l md:border-n-weak md:pl-4">
            <p class="mb-2 text-xs font-semibold uppercase text-n-teal-11">
              {{ t('AI_ASSISTANT.WEBSITE_IMPORT.SUGGESTED') }}
            </p>
            <p
              class="m-0 whitespace-pre-wrap break-words text-sm leading-6 text-n-slate-12"
            >
              {{ websiteImport.proposed_sections[key] }}
            </p>
          </div>
        </label>
      </template>
    </div>

    <template #footer>
      <div class="flex w-full justify-end gap-2">
        <Button
          variant="ghost"
          color="slate"
          :label="t('AI_ASSISTANT.WEBSITE_IMPORT.CANCEL')"
          @click="dialog.close()"
        />
        <Button
          v-if="isReady"
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
