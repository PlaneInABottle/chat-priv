<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import AiKnowledgeSourcesAPI from 'dashboard/api/aiKnowledgeSources';
import Button from 'dashboard/components-next/button/Button.vue';
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

const selectedIds = computed(() => new Set(props.modelValue.map(Number)));
const atSelectionLimit = computed(
  () => selectedIds.value.size >= MAX_SELECTED_SOURCES
);

const isSourceDisabled = sourceId =>
  props.disabled ||
  (atSelectionLimit.value && !selectedIds.value.has(sourceId));

const toggleSource = sourceId => {
  if (props.disabled) return;

  const nextIds = new Set(selectedIds.value);
  if (nextIds.has(sourceId)) nextIds.delete(sourceId);
  else if (!atSelectionLimit.value) nextIds.add(sourceId);
  emit('update:modelValue', Array.from(nextIds));
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
      <Button
        icon="i-lucide-library"
        variant="outline"
        color="slate"
        :label="t('AI_KNOWLEDGE.ACTIONS.MANAGE')"
        @click="openLibrary"
      />
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

    <div v-else class="grid grid-cols-1 gap-3 lg:grid-cols-2">
      <label
        v-for="source in sources"
        :key="source.id"
        class="flex min-w-0 cursor-pointer items-start gap-3 rounded-lg border border-n-weak bg-n-alpha-1 p-4 hover:bg-n-alpha-2"
        :class="{
          'cursor-not-allowed opacity-60': isSourceDisabled(source.id),
        }"
      >
        <input
          type="checkbox"
          class="mt-0.5 size-4 rounded border-n-slate-6 text-n-brand focus:ring-n-brand"
          :checked="selectedIds.has(source.id)"
          :disabled="isSourceDisabled(source.id)"
          :data-testid="`knowledge-source-${source.id}`"
          @change="toggleSource(source.id)"
        />
        <span class="min-w-0 flex-1">
          <span class="block truncate text-sm font-medium text-n-slate-12">
            {{ source.name }}
          </span>
          <span class="mt-1 block truncate text-xs text-n-slate-10">
            {{ source.content_preview || source.content }}
          </span>
          <span class="mt-2 block text-xs text-n-slate-9">
            {{
              t('AI_KNOWLEDGE.CHARACTERS', {
                count: source.character_count,
              })
            }}
          </span>
        </span>
      </label>
    </div>
  </section>
</template>
