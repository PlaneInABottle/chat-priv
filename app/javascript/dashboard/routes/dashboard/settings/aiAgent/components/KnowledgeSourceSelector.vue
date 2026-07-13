<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import AiKnowledgeSourcesAPI from 'dashboard/api/aiKnowledgeSources';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  modelValue: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);

const MAX_SELECTED_SOURCES = 20;

const { t } = useI18n();
const router = useRouter();
const sources = ref([]);
const isLoading = ref(false);
const pickerDialog = ref(null);
const searchQuery = ref('');
const draftIds = ref([]);

const selectedIds = computed(() => new Set(props.modelValue.map(Number)));
const selectedSources = computed(() =>
  sources.value.filter(source => selectedIds.value.has(source.id))
);
const draftIdSet = computed(() => new Set(draftIds.value.map(Number)));
const draftAtSelectionLimit = computed(
  () => draftIdSet.value.size >= MAX_SELECTED_SOURCES
);
const filteredSources = computed(() => {
  const query = searchQuery.value.trim().toLocaleLowerCase();
  if (!query) return sources.value;

  return sources.value.filter(source =>
    [source.name, source.content_preview].some(value =>
      value?.toLocaleLowerCase().includes(query)
    )
  );
});

const isDraftSourceDisabled = source =>
  (source.available === false || draftAtSelectionLimit.value) &&
  !draftIdSet.value.has(source.id);

const toggleDraftSource = source => {
  const sourceId = Number(source.id);
  const nextIds = new Set(draftIdSet.value);
  if (nextIds.has(sourceId)) nextIds.delete(sourceId);
  else if (!draftAtSelectionLimit.value && source.available !== false)
    nextIds.add(sourceId);
  draftIds.value = Array.from(nextIds);
};

const openPicker = () => {
  if (props.disabled) return;
  draftIds.value = Array.from(selectedIds.value);
  searchQuery.value = '';
  pickerDialog.value?.open();
};

const applySelection = () => {
  emit(
    'update:modelValue',
    [...draftIds.value].sort((a, b) => a - b)
  );
  pickerDialog.value?.close();
};

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

const openLibrary = () => router.push({ name: 'ai_knowledge_sources' });

onMounted(loadSources);
</script>

<template>
  <section class="flex min-w-0 flex-col gap-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ t('AI_KNOWLEDGE.SELECTOR.TITLE') }}
        </h2>
        <p class="mb-0 mt-1 text-sm text-n-slate-11">
          {{ t('AI_KNOWLEDGE.SELECTOR.DESCRIPTION') }}
        </p>
        <p class="mb-0 mt-1 text-xs text-n-slate-9">
          {{
            t('AI_KNOWLEDGE.SELECTOR.COUNT', {
              count: selectedIds.size,
              limit: MAX_SELECTED_SOURCES,
            })
          }}
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <Button
          icon="i-lucide-list-plus"
          variant="outline"
          color="slate"
          :label="t('AI_KNOWLEDGE.SELECTOR.CHOOSE')"
          :disabled="disabled"
          @click="openPicker"
        />
        <Button
          icon="i-lucide-library"
          variant="ghost"
          color="slate"
          :label="t('AI_KNOWLEDGE.ACTIONS.MANAGE')"
          @click="openLibrary"
        />
      </div>
    </div>

    <div
      v-if="isLoading"
      class="flex items-center gap-2 py-8 text-sm text-n-slate-11"
    >
      <span
        aria-hidden="true"
        class="i-lucide-loader-circle size-4 animate-spin"
      />
      {{ t('AI_KNOWLEDGE.LOADING') }}
    </div>

    <div
      v-else-if="!sources.length"
      class="border-y border-n-weak py-10 text-center"
    >
      <span
        aria-hidden="true"
        class="i-lucide-library mx-auto block size-6 text-n-slate-9"
      />
      <p class="mb-0 mt-3 text-sm font-medium text-n-slate-12">
        {{ t('AI_KNOWLEDGE.EMPTY.TITLE') }}
      </p>
      <Button
        class="mt-4"
        icon="i-lucide-plus"
        variant="outline"
        color="slate"
        :label="t('AI_KNOWLEDGE.ACTIONS.ADD')"
        @click="openLibrary"
      />
    </div>

    <div
      v-else-if="!selectedSources.length"
      class="border-y border-n-weak py-8 text-center text-sm text-n-slate-10"
    >
      {{ t('AI_KNOWLEDGE.SELECTOR.NONE_SELECTED') }}
    </div>

    <div v-else class="flex flex-col border-y border-n-weak">
      <div
        v-for="source in selectedSources"
        :key="source.id"
        class="flex min-w-0 items-center gap-3 border-b border-n-weak py-3 last:border-b-0"
      >
        <span
          aria-hidden="true"
          class="i-lucide-file-text size-4 text-n-slate-9"
        />
        <span class="min-w-0 flex-1">
          <span class="block truncate text-sm font-medium text-n-slate-12">
            {{ source.name }}
          </span>
          <span class="mt-1 block truncate text-xs text-n-slate-10">
            {{
              source.content_preview || t('AI_KNOWLEDGE.STATUS.WAITING_CONTENT')
            }}
          </span>
        </span>
      </div>
    </div>
  </section>

  <Dialog
    ref="pickerDialog"
    width="2xl"
    position="top"
    :title="t('AI_KNOWLEDGE.SELECTOR.DIALOG_TITLE')"
    :description="t('AI_KNOWLEDGE.SELECTOR.DIALOG_DESCRIPTION')"
    :confirm-button-label="t('AI_KNOWLEDGE.SELECTOR.APPLY')"
    @confirm="applySelection"
  >
    <div class="flex min-h-0 flex-col gap-3">
      <label class="relative block">
        <span
          aria-hidden="true"
          class="pointer-events-none absolute inset-y-0 left-0 flex w-10 items-center justify-center text-n-slate-9"
        >
          <span class="i-lucide-search size-4" />
        </span>
        <input
          v-model="searchQuery"
          type="search"
          name="knowledge-source-search"
          autocomplete="off"
          :aria-label="t('AI_KNOWLEDGE.SELECTOR.SEARCH')"
          :placeholder="t('AI_KNOWLEDGE.SELECTOR.SEARCH')"
          class="h-10 w-full rounded-lg border border-n-weak bg-n-alpha-1 pl-10 pr-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        />
      </label>
      <p class="m-0 text-xs text-n-slate-10">
        {{
          t('AI_KNOWLEDGE.SELECTOR.COUNT', {
            count: draftIdSet.size,
            limit: MAX_SELECTED_SOURCES,
          })
        }}
      </p>
      <div class="max-h-[50dvh] overflow-y-auto border-y border-n-weak">
        <label
          v-for="source in filteredSources"
          :key="source.id"
          class="flex cursor-pointer items-start gap-3 border-b border-n-weak py-3 last:border-b-0"
          :class="{
            'cursor-not-allowed opacity-60': isDraftSourceDisabled(source),
          }"
        >
          <input
            type="checkbox"
            class="mt-0.5 size-4 rounded border-n-slate-6 text-n-brand focus:ring-n-brand"
            :checked="draftIdSet.has(source.id)"
            :disabled="isDraftSourceDisabled(source)"
            :data-testid="`knowledge-source-${source.id}`"
            @change="toggleDraftSource(source)"
          />
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm font-medium text-n-slate-12">{{
              source.name
            }}</span>
            <span class="mt-1 block truncate text-xs text-n-slate-10">
              {{
                source.content_preview ||
                t('AI_KNOWLEDGE.STATUS.WAITING_CONTENT')
              }}
            </span>
          </span>
        </label>
        <p
          v-if="!filteredSources.length"
          class="m-0 py-10 text-center text-sm text-n-slate-10"
        >
          {{ t('AI_KNOWLEDGE.SELECTOR.NO_MATCHES') }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
