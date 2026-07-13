<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import AiKnowledgeSourcesAPI from 'dashboard/api/aiKnowledgeSources';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const CONTENT_LIMIT = 100000;
const ACTIVE_SYNC_STATUSES = ['pending', 'syncing'];

const { t } = useI18n();
const sources = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);
const isDeleting = ref(false);
const syncingSourceIds = ref(new Set());
const editorDialog = ref(null);
const deleteDialog = ref(null);
const editingSourceId = ref(null);
const sourceToDelete = ref(null);
const form = ref({
  name: '',
  content: '',
  source_type: 'manual',
  website_url: '',
});
let refreshTimer;

const isEditing = computed(() => Boolean(editingSourceId.value));
const isWebsiteForm = computed(() => form.value.source_type === 'website');
const characterCount = computed(() => form.value.content.length);
const canSave = computed(
  () =>
    form.value.name.trim().length > 0 &&
    (isWebsiteForm.value
      ? form.value.website_url.trim().length > 0
      : form.value.content.trim().length > 0 &&
        characterCount.value <= CONTENT_LIMIT) &&
    !isSaving.value
);

const assistantCount = source =>
  (source.assigned_ai_agent_ids?.length || 0) +
  (source.assigned_voice_agent_ids?.length || 0);

const isSourceSyncing = source =>
  ACTIVE_SYNC_STATUSES.includes(source.sync_status) ||
  syncingSourceIds.value.has(source.id);

const loadSources = async function refreshSources() {
  isLoading.value = sources.value.length === 0;
  try {
    const { data } = await AiKnowledgeSourcesAPI.get();
    sources.value = Array.isArray(data) ? data : [];
  } catch {
    useAlert(t('AI_KNOWLEDGE.ERROR.LOAD'));
  } finally {
    isLoading.value = false;
    window.clearTimeout(refreshTimer);
    if (sources.value.some(isSourceSyncing)) {
      refreshTimer = window.setTimeout(refreshSources, 1500);
    }
  }
};

const openCreate = () => {
  editingSourceId.value = null;
  form.value = {
    name: '',
    content: '',
    source_type: 'manual',
    website_url: '',
  };
  editorDialog.value?.open();
};

const openEdit = async source => {
  try {
    const { data } = await AiKnowledgeSourcesAPI.show(source.id);
    editingSourceId.value = data.id;
    form.value = {
      name: data.name,
      content: data.content || '',
      source_type: data.source_type,
      website_url: data.website_url || '',
    };
    editorDialog.value?.open();
  } catch {
    useAlert(t('AI_KNOWLEDGE.ERROR.LOAD'));
  }
};

const saveSource = async () => {
  if (!canSave.value) return;

  isSaving.value = true;
  const payload = isWebsiteForm.value
    ? {
        name: form.value.name.trim(),
        source_type: form.value.source_type,
        website_url: form.value.website_url.trim(),
      }
    : {
        name: form.value.name.trim(),
        source_type: form.value.source_type,
        content: form.value.content.trim(),
      };
  try {
    const { data } = isEditing.value
      ? await AiKnowledgeSourcesAPI.update(editingSourceId.value, payload)
      : await AiKnowledgeSourcesAPI.create(payload);
    const existingIndex = sources.value.findIndex(
      source => source.id === data.id
    );
    if (existingIndex >= 0) sources.value.splice(existingIndex, 1, data);
    else sources.value.unshift(data);
    editorDialog.value?.close();
    useAlert(t('AI_KNOWLEDGE.SUCCESS.SAVED'));
    if (isSourceSyncing(data)) {
      window.clearTimeout(refreshTimer);
      refreshTimer = window.setTimeout(loadSources, 1500);
    }
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('AI_KNOWLEDGE.ERROR.SAVE'));
  } finally {
    isSaving.value = false;
  }
};

const syncSource = async source => {
  if (isSourceSyncing(source)) return;

  syncingSourceIds.value = new Set([...syncingSourceIds.value, source.id]);
  try {
    const { data } = await AiKnowledgeSourcesAPI.sync(source.id);
    const sourceIndex = sources.value.findIndex(item => item.id === data.id);
    if (sourceIndex >= 0) sources.value.splice(sourceIndex, 1, data);
    useAlert(t('AI_KNOWLEDGE.SUCCESS.SYNC_QUEUED'));
    window.clearTimeout(refreshTimer);
    refreshTimer = window.setTimeout(loadSources, 1500);
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('AI_KNOWLEDGE.ERROR.SYNC'));
  } finally {
    const nextIds = new Set(syncingSourceIds.value);
    nextIds.delete(source.id);
    syncingSourceIds.value = nextIds;
  }
};

const openDelete = source => {
  sourceToDelete.value = source;
  deleteDialog.value?.open();
};

const deleteSource = async () => {
  if (!sourceToDelete.value) return;

  isDeleting.value = true;
  try {
    await AiKnowledgeSourcesAPI.delete(sourceToDelete.value.id);
    sources.value = sources.value.filter(
      source => source.id !== sourceToDelete.value.id
    );
    sourceToDelete.value = null;
    deleteDialog.value?.close();
    useAlert(t('AI_KNOWLEDGE.SUCCESS.DELETED'));
  } catch {
    useAlert(t('AI_KNOWLEDGE.ERROR.DELETE'));
  } finally {
    isDeleting.value = false;
  }
};

onMounted(loadSources);
onBeforeUnmount(() => window.clearTimeout(refreshTimer));
</script>

<template>
  <SettingsLayout :is-loading="isLoading">
    <template #header>
      <BaseSettingsHeader
        :title="t('AI_KNOWLEDGE.TITLE')"
        :description="t('AI_KNOWLEDGE.DESCRIPTION')"
        feature-name="ai_agent"
      >
        <template #actions>
          <Button
            icon="i-lucide-plus"
            :label="t('AI_KNOWLEDGE.ACTIONS.ADD')"
            @click="openCreate"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div
        v-if="!sources.length && !isLoading"
        class="border-y border-n-weak py-20 text-center"
      >
        <span
          aria-hidden="true"
          class="i-lucide-library mx-auto block size-7 text-n-slate-9"
        />
        <h2 class="mb-0 mt-4 text-base font-semibold text-n-slate-12">
          {{ t('AI_KNOWLEDGE.EMPTY.TITLE') }}
        </h2>
        <p class="mx-auto mb-0 mt-1 max-w-lg text-sm text-n-slate-10">
          {{ t('AI_KNOWLEDGE.EMPTY.DESCRIPTION') }}
        </p>
        <Button
          class="mt-5"
          icon="i-lucide-plus"
          :label="t('AI_KNOWLEDGE.ACTIONS.ADD')"
          @click="openCreate"
        />
      </div>

      <div
        v-else
        class="overflow-hidden rounded-lg border border-n-weak bg-n-alpha-1"
      >
        <div
          class="hidden grid-cols-[minmax(0,1fr)_130px_150px_120px] gap-4 border-b border-n-weak bg-n-alpha-2 px-4 py-2 text-xs font-medium text-n-slate-11 md:grid"
        >
          <span>{{ t('AI_KNOWLEDGE.COLUMNS.SOURCE') }}</span>
          <span>{{ t('AI_KNOWLEDGE.COLUMNS.ASSISTANTS') }}</span>
          <span>{{ t('AI_KNOWLEDGE.COLUMNS.FRESHNESS') }}</span>
          <span class="sr-only">{{ t('AI_KNOWLEDGE.COLUMNS.ACTIONS') }}</span>
        </div>

        <article
          v-for="source in sources"
          :key="source.id"
          class="grid min-w-0 grid-cols-1 gap-3 border-b border-n-weak p-4 last:border-b-0 md:grid-cols-[minmax(0,1fr)_130px_150px_120px] md:items-center md:gap-4"
        >
          <div class="min-w-0">
            <div class="flex min-w-0 items-center gap-2">
              <span
                aria-hidden="true"
                class="size-4 shrink-0 text-n-slate-9"
                :class="
                  source.source_type === 'website'
                    ? 'i-lucide-globe-2'
                    : 'i-lucide-file-text'
                "
              />
              <h2 class="m-0 truncate text-sm font-medium text-n-slate-12">
                {{ source.name }}
              </h2>
            </div>
            <p
              v-if="source.website_url"
              class="mb-0 mt-1 truncate text-xs text-n-slate-9"
              :title="source.website_url"
            >
              {{ source.website_url }}
            </p>
            <p class="mb-0 mt-1 truncate text-sm text-n-slate-10">
              {{
                source.content_preview ||
                t('AI_KNOWLEDGE.STATUS.WAITING_CONTENT')
              }}
            </p>
            <span class="mt-1 block text-xs text-n-slate-9 md:hidden">
              {{
                t('AI_KNOWLEDGE.CHARACTERS', { count: source.character_count })
              }}
            </span>
          </div>
          <span class="text-sm text-n-slate-11">
            {{
              t('AI_KNOWLEDGE.ASSISTANT_COUNT', {
                count: assistantCount(source),
              })
            }}
          </span>
          <div class="min-w-0 text-sm text-n-slate-10">
            <span
              v-if="isSourceSyncing(source)"
              class="inline-flex items-center gap-1.5 text-n-amber-11"
            >
              <span
                aria-hidden="true"
                class="i-lucide-loader-circle size-3.5 animate-spin"
              />
              {{
                source.sync_status === 'pending'
                  ? t('AI_KNOWLEDGE.STATUS.PENDING')
                  : t('AI_KNOWLEDGE.STATUS.SYNCING')
              }}
            </span>
            <span
              v-else-if="source.sync_status === 'failed'"
              class="block text-n-ruby-11"
              :title="source.sync_error"
            >
              {{ t('AI_KNOWLEDGE.STATUS.FAILED') }}
            </span>
            <time
              v-else-if="source.source_type === 'website'"
              :datetime="source.last_synced_at"
            >
              {{
                source.last_synced_at
                  ? t('AI_KNOWLEDGE.STATUS.SYNCED_DATE', {
                      date: new Date(
                        source.last_synced_at
                      ).toLocaleDateString(),
                    })
                  : t('AI_KNOWLEDGE.STATUS.NOT_SYNCED')
              }}
            </time>
            <time v-else :datetime="source.updated_at">
              {{
                t('AI_KNOWLEDGE.STATUS.UPDATED_DATE', {
                  date: new Date(source.updated_at).toLocaleDateString(),
                })
              }}
            </time>
            <span
              v-if="source.sync_status === 'failed' && source.sync_error"
              class="mt-0.5 block truncate text-xs text-n-ruby-10"
              :title="source.sync_error"
            >
              {{ source.sync_error }}
            </span>
            <span
              v-if="source.sync_status === 'failed' && source.last_synced_at"
              class="mt-0.5 block truncate text-xs text-n-slate-9"
            >
              {{
                t('AI_KNOWLEDGE.STATUS.LAST_SYNCED_DATE', {
                  date: new Date(source.last_synced_at).toLocaleDateString(),
                })
              }}
            </span>
          </div>
          <div class="flex justify-end gap-1">
            <Button
              v-if="source.source_type === 'website'"
              v-tooltip="t('AI_KNOWLEDGE.ACTIONS.SYNC')"
              icon="i-lucide-refresh-cw"
              variant="ghost"
              color="slate"
              size="sm"
              :disabled="isSourceSyncing(source)"
              :is-loading="isSourceSyncing(source)"
              :aria-label="t('AI_KNOWLEDGE.ACTIONS.SYNC')"
              @click="syncSource(source)"
            />
            <Button
              v-tooltip="t('AI_KNOWLEDGE.ACTIONS.EDIT')"
              icon="i-lucide-pencil"
              variant="ghost"
              color="slate"
              size="sm"
              :aria-label="t('AI_KNOWLEDGE.ACTIONS.EDIT')"
              @click="openEdit(source)"
            />
            <Button
              v-tooltip="t('AI_KNOWLEDGE.ACTIONS.DELETE')"
              icon="i-lucide-trash-2"
              variant="ghost"
              color="ruby"
              size="sm"
              :aria-label="t('AI_KNOWLEDGE.ACTIONS.DELETE')"
              @click="openDelete(source)"
            />
          </div>
        </article>
      </div>
    </template>
  </SettingsLayout>

  <Dialog
    ref="editorDialog"
    width="2xl"
    :title="
      isEditing
        ? t('AI_KNOWLEDGE.EDITOR.EDIT_TITLE')
        : t('AI_KNOWLEDGE.EDITOR.CREATE_TITLE')
    "
    :confirm-button-label="
      !isEditing && isWebsiteForm
        ? t('AI_KNOWLEDGE.ACTIONS.ADD_AND_SYNC')
        : t('AI_KNOWLEDGE.ACTIONS.SAVE')
    "
    :cancel-button-label="t('AI_KNOWLEDGE.ACTIONS.CANCEL')"
    :disable-confirm-button="!canSave"
    :is-loading="isSaving"
    @confirm="saveSource"
  >
    <div class="flex flex-col gap-5">
      <div v-if="!isEditing" class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('AI_KNOWLEDGE.EDITOR.TYPE') }}
        </span>
        <div
          role="group"
          :aria-label="t('AI_KNOWLEDGE.EDITOR.TYPE')"
          class="grid grid-cols-2 rounded-lg bg-n-alpha-black2 p-1"
        >
          <button
            type="button"
            class="flex min-w-0 items-center justify-center gap-2 rounded-md px-3 py-2 text-sm text-n-slate-11"
            :class="{
              'bg-n-solid-2 font-medium text-n-slate-12 shadow-sm':
                !isWebsiteForm,
            }"
            :aria-pressed="!isWebsiteForm"
            @click="form.source_type = 'manual'"
          >
            <span aria-hidden="true" class="i-lucide-file-text size-4" />
            {{ t('AI_KNOWLEDGE.EDITOR.MANUAL') }}
          </button>
          <button
            type="button"
            class="flex min-w-0 items-center justify-center gap-2 rounded-md px-3 py-2 text-sm text-n-slate-11"
            :class="{
              'bg-n-solid-2 font-medium text-n-slate-12 shadow-sm':
                isWebsiteForm,
            }"
            :aria-pressed="isWebsiteForm"
            @click="form.source_type = 'website'"
          >
            <span aria-hidden="true" class="i-lucide-globe-2 size-4" />
            {{ t('AI_KNOWLEDGE.EDITOR.WEBSITE') }}
          </button>
        </div>
        <p class="mb-0 text-xs text-n-slate-10">
          {{
            isWebsiteForm
              ? t('AI_KNOWLEDGE.EDITOR.WEBSITE_DESCRIPTION')
              : t('AI_KNOWLEDGE.EDITOR.MANUAL_DESCRIPTION')
          }}
        </p>
      </div>
      <Input
        v-model="form.name"
        :label="t('AI_KNOWLEDGE.EDITOR.NAME')"
        :placeholder="t('AI_KNOWLEDGE.EDITOR.NAME_PLACEHOLDER')"
        maxlength="120"
      />
      <Input
        v-if="isWebsiteForm"
        v-model="form.website_url"
        type="url"
        :label="t('AI_KNOWLEDGE.EDITOR.WEBSITE_URL')"
        :placeholder="t('AI_KNOWLEDGE.EDITOR.WEBSITE_URL_PLACEHOLDER')"
      />
      <label v-else class="flex min-w-0 flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('AI_KNOWLEDGE.EDITOR.CONTENT') }}
        </span>
        <textarea
          v-model="form.content"
          rows="14"
          :maxlength="CONTENT_LIMIT"
          :placeholder="t('AI_KNOWLEDGE.EDITOR.CONTENT_PLACEHOLDER')"
          class="min-h-64 w-full resize-y rounded-lg border-0 bg-n-alpha-black2 px-3 py-2 text-sm leading-6 text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
        />
        <span class="text-right text-xs text-n-slate-10">
          {{
            t('AI_KNOWLEDGE.EDITOR.CHARACTER_LIMIT', {
              count: characterCount,
              limit: CONTENT_LIMIT,
            })
          }}
        </span>
      </label>
      <div
        v-if="isEditing && isWebsiteForm && form.content"
        class="flex min-w-0 flex-col gap-1.5"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('AI_KNOWLEDGE.EDITOR.SYNCED_CONTENT') }}
        </span>
        <div
          class="max-h-64 overflow-y-auto whitespace-pre-wrap rounded-lg bg-n-alpha-black2 px-3 py-2 text-sm leading-6 text-n-slate-11"
        >
          {{ form.content }}
        </div>
        <p class="mb-0 text-xs text-n-slate-9">
          {{ t('AI_KNOWLEDGE.EDITOR.SYNCED_CONTENT_DESCRIPTION') }}
        </p>
      </div>
    </div>
  </Dialog>

  <Dialog
    ref="deleteDialog"
    type="alert"
    :title="t('AI_KNOWLEDGE.DELETE.TITLE')"
    :description="
      t('AI_KNOWLEDGE.DELETE.DESCRIPTION', {
        name: sourceToDelete?.name || '',
        count: sourceToDelete ? assistantCount(sourceToDelete) : 0,
      })
    "
    :confirm-button-label="t('AI_KNOWLEDGE.ACTIONS.DELETE')"
    :cancel-button-label="t('AI_KNOWLEDGE.ACTIONS.CANCEL')"
    :is-loading="isDeleting"
    @confirm="deleteSource"
  />
</template>
