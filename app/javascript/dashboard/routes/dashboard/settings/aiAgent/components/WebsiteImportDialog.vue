<script setup>
import { computed, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import AiAgentWebsiteImportsAPI from 'dashboard/api/aiAgentWebsiteImports';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  aiAgentId: { type: Number, required: true },
  currentDocument: { type: Object, required: true },
  defaultWebsite: { type: String, default: '' },
});

const emit = defineEmits(['applied']);
const { t } = useI18n();
const dialog = ref(null);
const websiteUrl = ref('');
const websiteImport = ref(null);
const selectedSections = ref([]);
const isStarting = ref(false);
const isApplying = ref(false);
const isDialogOpen = ref(false);
let pollTimer = null;

const api = computed(() => new AiAgentWebsiteImportsAPI(props.aiAgentId));
const isRunning = computed(() =>
  ['pending', 'running'].includes(websiteImport.value?.status)
);
const isReady = computed(() => websiteImport.value?.status === 'ready');
const changedSections = computed(
  () => websiteImport.value?.changed_sections || []
);
const canApply = computed(
  () => isReady.value && selectedSections.value.length > 0
);

const sectionLabel = key =>
  t(`AI_ASSISTANT.INSTRUCTIONS.SECTIONS.${key.toUpperCase()}.TITLE`);

const stopPolling = () => {
  if (pollTimer) clearTimeout(pollTimer);
  pollTimer = null;
};

const pollImport = async () => {
  try {
    const { data } = await api.value.show(websiteImport.value.id);
    websiteImport.value = data;
    if (data.status === 'ready') selectedSections.value = data.changed_sections;

    stopPolling();
    if (['pending', 'running'].includes(data.status)) {
      pollTimer = setTimeout(pollImport, 1500);
    }
  } catch {
    stopPolling();
    pollTimer = setTimeout(pollImport, 3000);
  }
};

const startImport = async () => {
  if (!websiteUrl.value.trim()) return;

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
    useAlert(
      error.response?.data?.error ||
        t('AI_ASSISTANT.WEBSITE_IMPORT.ERROR.START')
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
      expected_draft_fingerprint: websiteImport.value.current_draft_fingerprint,
    });
    emit('applied');
    dialog.value.close();
    useAlert(t('AI_ASSISTANT.WEBSITE_IMPORT.APPLIED'));
  } catch (error) {
    useAlert(
      error.response?.data?.error ||
        t('AI_ASSISTANT.WEBSITE_IMPORT.ERROR.APPLY')
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
    overflow-y-auto
    @close="handleClose"
  >
    <div
      class="flex max-h-[70dvh] min-h-72 flex-col gap-5 overflow-y-auto pr-1"
    >
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
            required
            :placeholder="t('AI_ASSISTANT.WEBSITE_IMPORT.URL_PLACEHOLDER')"
            class="mt-1 h-10 w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal"
          />
        </label>
        <Button
          type="submit"
          icon="i-lucide-scan-search"
          class="self-end"
          :label="t('AI_ASSISTANT.WEBSITE_IMPORT.ANALYZE')"
          :is-loading="isStarting"
          :disabled="!websiteUrl.trim()"
        />
      </form>

      <div
        v-else-if="isRunning"
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
        class="flex flex-1 flex-col items-center justify-center gap-3 py-12 text-center"
      >
        <Icon icon="i-lucide-circle-alert" class="size-6 text-n-ruby-11" />
        <p class="m-0 max-w-md text-sm text-n-slate-11">
          {{
            websiteImport.error_message ||
            t('AI_ASSISTANT.WEBSITE_IMPORT.ERROR.START')
          }}
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
          <Icon icon="i-lucide-info" class="mt-0.5 size-4 text-n-blue-11" />
          <p class="m-0 text-sm text-n-blue-12">
            {{ t('AI_ASSISTANT.WEBSITE_IMPORT.REVIEW_HELP') }}
          </p>
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
