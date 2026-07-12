<script setup>
import { computed, onMounted, ref } from 'vue';
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

const { t } = useI18n();
const sources = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);
const isDeleting = ref(false);
const editorDialog = ref(null);
const deleteDialog = ref(null);
const editingSourceId = ref(null);
const sourceToDelete = ref(null);
const form = ref({ name: '', content: '' });

const isEditing = computed(() => Boolean(editingSourceId.value));
const characterCount = computed(() => form.value.content.length);
const canSave = computed(
  () =>
    form.value.name.trim().length > 0 &&
    form.value.content.trim().length > 0 &&
    characterCount.value <= CONTENT_LIMIT &&
    !isSaving.value
);

const assistantCount = source =>
  (source.assigned_ai_agent_ids?.length || 0) +
  (source.assigned_voice_agent_ids?.length || 0);

const loadSources = async () => {
  isLoading.value = true;
  try {
    const { data } = await AiKnowledgeSourcesAPI.get();
    sources.value = Array.isArray(data) ? data : [];
  } catch {
    useAlert(t('AI_KNOWLEDGE.ERROR.LOAD'));
  } finally {
    isLoading.value = false;
  }
};

const openCreate = () => {
  editingSourceId.value = null;
  form.value = { name: '', content: '' };
  editorDialog.value?.open();
};

const openEdit = async source => {
  try {
    const { data } = await AiKnowledgeSourcesAPI.show(source.id);
    editingSourceId.value = data.id;
    form.value = { name: data.name, content: data.content };
    editorDialog.value?.open();
  } catch {
    useAlert(t('AI_KNOWLEDGE.ERROR.LOAD'));
  }
};

const saveSource = async () => {
  if (!canSave.value) return;

  isSaving.value = true;
  const payload = {
    name: form.value.name.trim(),
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
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('AI_KNOWLEDGE.ERROR.SAVE'));
  } finally {
    isSaving.value = false;
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
          class="hidden grid-cols-[minmax(0,1fr)_130px_120px_88px] gap-4 border-b border-n-weak bg-n-alpha-2 px-4 py-2 text-xs font-medium text-n-slate-11 md:grid"
        >
          <span>{{ t('AI_KNOWLEDGE.COLUMNS.SOURCE') }}</span>
          <span>{{ t('AI_KNOWLEDGE.COLUMNS.ASSISTANTS') }}</span>
          <span>{{ t('AI_KNOWLEDGE.COLUMNS.UPDATED') }}</span>
          <span class="sr-only">{{ t('AI_KNOWLEDGE.COLUMNS.ACTIONS') }}</span>
        </div>

        <article
          v-for="source in sources"
          :key="source.id"
          class="grid min-w-0 grid-cols-1 gap-3 border-b border-n-weak p-4 last:border-b-0 md:grid-cols-[minmax(0,1fr)_130px_120px_88px] md:items-center md:gap-4"
        >
          <div class="min-w-0">
            <h2 class="m-0 truncate text-sm font-medium text-n-slate-12">
              {{ source.name }}
            </h2>
            <p class="mb-0 mt-1 truncate text-sm text-n-slate-10">
              {{ source.content_preview || source.content }}
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
          <time class="text-sm text-n-slate-10" :datetime="source.updated_at">
            {{ new Date(source.updated_at).toLocaleDateString() }}
          </time>
          <div class="flex justify-end gap-1">
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
    :confirm-button-label="t('AI_KNOWLEDGE.ACTIONS.SAVE')"
    :cancel-button-label="t('AI_KNOWLEDGE.ACTIONS.CANCEL')"
    :disable-confirm-button="!canSave"
    :is-loading="isSaving"
    @confirm="saveSource"
  >
    <div class="flex flex-col gap-5">
      <Input
        v-model="form.name"
        :label="t('AI_KNOWLEDGE.EDITOR.NAME')"
        :placeholder="t('AI_KNOWLEDGE.EDITOR.NAME_PLACEHOLDER')"
        maxlength="120"
      />
      <label class="flex min-w-0 flex-col gap-1.5">
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
