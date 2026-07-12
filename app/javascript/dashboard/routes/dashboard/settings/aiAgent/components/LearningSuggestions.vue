<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';

import AiAgentLearningSuggestionsAPI from 'dashboard/api/aiAgentLearningSuggestions';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  aiAgentId: { type: Number, required: true },
  hasUnsavedInstructions: { type: Boolean, default: false },
});

const emit = defineEmits(['draftUpdated']);

const { t } = useI18n();
const store = useStore();
const suggestions = ref([]);
const reviewDrafts = ref({});
const isLoading = ref(false);
const applyingId = ref(null);
const dismissingId = ref(null);
const confirmDialog = ref(null);
let pollTimer;

const api = computed(() => new AiAgentLearningSuggestionsAPI(props.aiAgentId));
const accountId = computed(() => store.getters.getCurrentAccountId);
const activeStatuses = ['pending', 'analyzing', 'ready', 'failed'];
const historyStatuses = ['applied', 'dismissed', 'not_recommended'];
const sectionOptions = computed(() => [
  {
    value: 'business_context',
    label: t('AI_ASSISTANT.LEARNING.SECTIONS.BUSINESS_CONTEXT'),
  },
  {
    value: 'tasks',
    label: t('AI_ASSISTANT.LEARNING.SECTIONS.TASKS'),
  },
  {
    value: 'rules',
    label: t('AI_ASSISTANT.LEARNING.SECTIONS.RULES'),
  },
  {
    value: 'handoff',
    label: t('AI_ASSISTANT.LEARNING.SECTIONS.HANDOFF'),
  },
  {
    value: 'additional',
    label: t('AI_ASSISTANT.LEARNING.SECTIONS.ADDITIONAL'),
  },
]);
const destinationOptions = computed(() => [
  {
    value: 'knowledge',
    label: t('AI_ASSISTANT.LEARNING.DESTINATIONS.KNOWLEDGE'),
  },
  {
    value: 'instructions',
    label: t('AI_ASSISTANT.LEARNING.DESTINATIONS.INSTRUCTIONS'),
  },
]);
const activeSuggestions = computed(() =>
  suggestions.value.filter(item => activeStatuses.includes(item.status))
);
const historySuggestions = computed(() =>
  suggestions.value.filter(item => historyStatuses.includes(item.status))
);
const isAnalyzing = computed(() =>
  suggestions.value.some(item => ['pending', 'analyzing'].includes(item.status))
);
let loadSuggestions;

const syncReviewDraft = suggestion => {
  if (!suggestion.suggested_instruction || reviewDrafts.value[suggestion.id]) {
    return;
  }

  reviewDrafts.value[suggestion.id] = {
    suggested_instruction: suggestion.suggested_instruction,
    destination: suggestion.destination || 'instructions',
    target_section: suggestion.target_section,
    source_name: suggestion.source_name || '',
  };
};

const isKnowledgeDraft = suggestion =>
  reviewDrafts.value[suggestion.id]?.destination === 'knowledge';

const updateDestination = (suggestion, destination) => {
  const draft = reviewDrafts.value[suggestion.id];
  draft.destination = destination;
  if (destination === 'instructions' && !draft.target_section) {
    draft.target_section = 'additional';
  }
};

const canApplySuggestion = suggestion => {
  const draft = reviewDrafts.value[suggestion.id];
  if (!draft?.suggested_instruction.trim()) {
    return false;
  }

  if (props.hasUnsavedInstructions && draft.destination === 'instructions') {
    return false;
  }

  return draft.destination === 'knowledge'
    ? Boolean(draft.source_name.trim())
    : Boolean(draft.target_section);
};

const schedulePoll = () => {
  window.clearTimeout(pollTimer);
  if (isAnalyzing.value) {
    pollTimer = window.setTimeout(
      () => loadSuggestions({ showLoading: false }),
      2000
    );
  }
};

loadSuggestions = async ({ showLoading = true } = {}) => {
  if (showLoading) isLoading.value = true;
  try {
    const response = await api.value.get();
    suggestions.value = response.data;
    suggestions.value.forEach(syncReviewDraft);
    schedulePoll();
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) || t('AI_ASSISTANT.LEARNING.ERROR.LOAD')
    );
  } finally {
    if (showLoading) isLoading.value = false;
  }
};

const replaceSuggestion = suggestion => {
  const index = suggestions.value.findIndex(item => item.id === suggestion.id);
  if (index >= 0) suggestions.value.splice(index, 1, suggestion);
};

const applySuggestion = async suggestion => {
  const draft = reviewDrafts.value[suggestion.id];
  if (!canApplySuggestion(suggestion)) return;

  applyingId.value = suggestion.id;
  try {
    const response = await api.value.applySuggestion(suggestion.id, {
      suggested_instruction: draft.suggested_instruction.trim(),
      destination: draft.destination,
      target_section: draft.target_section,
      source_name: draft.source_name.trim(),
    });
    replaceSuggestion(response.data);
    if (!props.hasUnsavedInstructions) {
      const refreshedAgent = await store.dispatch(
        'aiAgent/refresh',
        props.aiAgentId
      );
      if (refreshedAgent) emit('draftUpdated');
    }
    useAlert(t('AI_ASSISTANT.LEARNING.APPLIED'));
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) || t('AI_ASSISTANT.LEARNING.ERROR.APPLY')
    );
  } finally {
    applyingId.value = null;
  }
};

const dismissSuggestion = async suggestion => {
  const confirmed = await confirmDialog.value.showConfirmation();
  if (!confirmed) return;

  dismissingId.value = suggestion.id;
  try {
    const response = await api.value.dismissSuggestion(suggestion.id);
    replaceSuggestion(response.data);
    useAlert(t('AI_ASSISTANT.LEARNING.DISMISSED'));
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) || t('AI_ASSISTANT.LEARNING.ERROR.DISMISS')
    );
  } finally {
    dismissingId.value = null;
  }
};

const statusAppearances = computed(() => ({
  pending: {
    icon: 'i-lucide-clock-3',
    classes: 'text-n-blue-11',
    label: t('AI_ASSISTANT.LEARNING.STATUS.PENDING'),
  },
  analyzing: {
    icon: 'i-lucide-loader-circle animate-spin',
    classes: 'text-n-blue-11',
    label: t('AI_ASSISTANT.LEARNING.STATUS.ANALYZING'),
  },
  ready: {
    icon: 'i-lucide-circle-check',
    classes: 'text-n-teal-11',
    label: t('AI_ASSISTANT.LEARNING.STATUS.READY'),
  },
  applied: {
    icon: 'i-lucide-check-check',
    classes: 'text-n-teal-11',
    label: t('AI_ASSISTANT.LEARNING.STATUS.APPLIED'),
  },
  dismissed: {
    icon: 'i-lucide-circle-minus',
    classes: 'text-n-slate-10',
    label: t('AI_ASSISTANT.LEARNING.STATUS.DISMISSED'),
  },
  failed: {
    icon: 'i-lucide-circle-alert',
    classes: 'text-n-ruby-11',
    label: t('AI_ASSISTANT.LEARNING.STATUS.FAILED'),
  },
  not_recommended: {
    icon: 'i-lucide-shield-minus',
    classes: 'text-n-slate-10',
    label: t('AI_ASSISTANT.LEARNING.STATUS.NOT_RECOMMENDED'),
  },
}));

const statusAppearance = status =>
  statusAppearances.value[status] || statusAppearances.value.pending;

const sourceLink = suggestion => {
  if (!suggestion.source_available) return null;

  return frontendURL(
    conversationUrl({
      accountId: accountId.value,
      id: suggestion.conversation_id,
    }),
    { messageId: suggestion.source_message_id }
  );
};

onMounted(loadSuggestions);
onBeforeUnmount(() => window.clearTimeout(pollTimer));
</script>

<template>
  <section class="flex min-w-0 flex-col gap-6" aria-labelledby="learning-title">
    <header class="border-b border-n-weak pb-5">
      <h2 id="learning-title" class="m-0 text-xl font-semibold text-n-slate-12">
        {{ t('AI_ASSISTANT.LEARNING.TITLE') }}
      </h2>
      <p class="mb-0 mt-1 max-w-2xl text-sm text-n-slate-11">
        {{ t('AI_ASSISTANT.LEARNING.DESCRIPTION') }}
      </p>
    </header>

    <div v-if="isLoading" class="py-12 text-center text-sm text-n-slate-10">
      {{ t('AI_ASSISTANT.LEARNING.LOADING') }}
    </div>
    <div
      v-else-if="!suggestions.length"
      class="border-y border-n-weak py-12 text-center"
    >
      <span
        aria-hidden="true"
        class="i-lucide-lightbulb mx-auto block size-6 text-n-slate-9"
      />
      <h3 class="mb-0 mt-3 text-sm font-semibold text-n-slate-12">
        {{ t('AI_ASSISTANT.LEARNING.EMPTY.TITLE') }}
      </h3>
      <p class="mx-auto mb-0 mt-1 max-w-lg text-sm text-n-slate-10">
        {{ t('AI_ASSISTANT.LEARNING.EMPTY.DESCRIPTION') }}
      </p>
    </div>

    <div v-else class="flex flex-col gap-6">
      <div
        v-if="activeSuggestions.length"
        class="flex flex-col border-y border-n-weak"
      >
        <article
          v-for="suggestion in activeSuggestions"
          :key="suggestion.id"
          class="flex min-w-0 flex-col gap-4 border-b border-n-weak px-1 py-5 last:border-b-0"
        >
          <div
            class="flex min-w-0 flex-wrap items-center justify-between gap-3"
          >
            <span
              class="inline-flex items-center gap-1.5 text-xs font-medium"
              :class="statusAppearance(suggestion.status).classes"
            >
              <span
                aria-hidden="true"
                class="size-3.5 flex-shrink-0"
                :class="statusAppearance(suggestion.status).icon"
              />
              {{ statusAppearance(suggestion.status).label }}
            </span>
            <a
              v-if="sourceLink(suggestion)"
              :href="sourceLink(suggestion)"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1.5 text-xs font-medium text-n-blue-11 hover:underline"
            >
              <span
                aria-hidden="true"
                class="i-lucide-external-link size-3.5"
              />
              {{ t('AI_ASSISTANT.LEARNING.OPEN_CONVERSATION') }}
            </a>
          </div>

          <div class="grid min-w-0 grid-cols-1 gap-4 lg:grid-cols-2">
            <div class="min-w-0">
              <p class="m-0 text-xs font-medium text-n-slate-10">
                {{ t('AI_ASSISTANT.LEARNING.CUSTOMER_MESSAGE') }}
              </p>
              <p
                class="mb-0 mt-1 whitespace-pre-wrap break-words text-sm text-n-slate-12"
              >
                {{ suggestion.customer_message }}
              </p>
            </div>
            <div class="min-w-0">
              <p class="m-0 text-xs font-medium text-n-slate-10">
                {{ t('AI_ASSISTANT.LEARNING.HUMAN_ANSWER') }}
              </p>
              <p
                class="mb-0 mt-1 whitespace-pre-wrap break-words text-sm text-n-slate-12"
              >
                {{ suggestion.human_answer }}
              </p>
            </div>
          </div>

          <div
            v-if="suggestion.status === 'ready'"
            class="grid min-w-0 grid-cols-1 gap-4 border-l-2 border-n-weak pl-4 lg:grid-cols-[minmax(0,1fr)_240px]"
          >
            <label
              class="flex min-w-0 flex-col gap-1.5 text-sm font-medium text-n-slate-12"
            >
              {{
                isKnowledgeDraft(suggestion)
                  ? t('AI_ASSISTANT.LEARNING.PROPOSED_KNOWLEDGE')
                  : t('AI_ASSISTANT.LEARNING.PROPOSED_INSTRUCTION')
              }}
              <textarea
                v-model="reviewDrafts[suggestion.id].suggested_instruction"
                :name="`learning-instruction-${suggestion.id}`"
                autocomplete="off"
                maxlength="5000"
                rows="4"
                class="min-h-28 resize-y rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 font-normal outline-none focus-visible:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/20"
              />
            </label>
            <div class="flex min-w-0 flex-col gap-3">
              <label
                class="flex min-w-0 flex-col gap-1.5 text-sm font-medium text-n-slate-12"
              >
                {{ t('AI_ASSISTANT.LEARNING.DESTINATION') }}
                <select
                  :value="reviewDrafts[suggestion.id].destination"
                  :name="`learning-destination-${suggestion.id}`"
                  class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal outline-none focus-visible:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/20"
                  @change="updateDestination(suggestion, $event.target.value)"
                >
                  <option
                    v-for="option in destinationOptions"
                    :key="option.value"
                    :value="option.value"
                  >
                    {{ option.label }}
                  </option>
                </select>
              </label>
              <label
                v-if="isKnowledgeDraft(suggestion)"
                class="flex min-w-0 flex-col gap-1.5 text-sm font-medium text-n-slate-12"
              >
                {{ t('AI_ASSISTANT.LEARNING.SOURCE_NAME') }}
                <input
                  v-model="reviewDrafts[suggestion.id].source_name"
                  :name="`learning-source-name-${suggestion.id}`"
                  maxlength="120"
                  class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal outline-none focus-visible:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/20"
                />
              </label>
              <label
                v-else
                class="flex min-w-0 flex-col gap-1.5 text-sm font-medium text-n-slate-12"
              >
                {{ t('AI_ASSISTANT.LEARNING.TARGET_SECTION') }}
                <select
                  v-model="reviewDrafts[suggestion.id].target_section"
                  :name="`learning-section-${suggestion.id}`"
                  class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal outline-none focus-visible:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/20"
                >
                  <option
                    v-for="option in sectionOptions"
                    :key="option.value"
                    :value="option.value"
                  >
                    {{ option.label }}
                  </option>
                </select>
              </label>
              <span class="font-normal text-n-slate-10">
                {{ suggestion.reason }}
              </span>
            </div>
          </div>

          <p
            v-else-if="suggestion.error_message"
            class="m-0 text-sm text-n-ruby-11"
          >
            {{ suggestion.error_message }}
          </p>

          <div class="flex flex-wrap justify-end gap-2">
            <Button
              variant="ghost"
              color="slate"
              :label="t('AI_ASSISTANT.LEARNING.DISMISS')"
              :is-loading="dismissingId === suggestion.id"
              :disabled="applyingId === suggestion.id"
              @click="dismissSuggestion(suggestion)"
            />
            <Button
              v-if="suggestion.status === 'ready'"
              :icon="
                isKnowledgeDraft(suggestion)
                  ? 'i-lucide-library-big'
                  : 'i-lucide-file-plus-2'
              "
              :label="
                isKnowledgeDraft(suggestion)
                  ? t('AI_ASSISTANT.LEARNING.ADD_TO_KNOWLEDGE')
                  : t('AI_ASSISTANT.LEARNING.APPLY_TO_DRAFT')
              "
              :is-loading="applyingId === suggestion.id"
              :disabled="!canApplySuggestion(suggestion)"
              @click="applySuggestion(suggestion)"
            />
          </div>
        </article>
      </div>

      <div
        v-else
        class="border-y border-n-weak py-8 text-center text-sm text-n-slate-10"
      >
        {{ t('AI_ASSISTANT.LEARNING.NO_OPEN') }}
      </div>

      <details
        v-if="historySuggestions.length"
        class="border-b border-n-weak pb-4"
      >
        <summary class="cursor-pointer text-sm font-medium text-n-slate-11">
          {{
            t('AI_ASSISTANT.LEARNING.HISTORY', {
              count: historySuggestions.length,
            })
          }}
        </summary>
        <div class="mt-3 flex flex-col border-y border-n-weak">
          <article
            v-for="suggestion in historySuggestions"
            :key="suggestion.id"
            class="flex min-w-0 flex-col gap-2 border-b border-n-weak px-1 py-4 last:border-b-0"
          >
            <div class="flex flex-wrap items-center justify-between gap-2">
              <span
                class="inline-flex items-center gap-1.5 text-xs font-medium"
                :class="statusAppearance(suggestion.status).classes"
              >
                <span
                  aria-hidden="true"
                  class="size-3.5 flex-shrink-0"
                  :class="statusAppearance(suggestion.status).icon"
                />
                {{ statusAppearance(suggestion.status).label }}
              </span>
              <a
                v-if="sourceLink(suggestion)"
                :href="sourceLink(suggestion)"
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center gap-1.5 text-xs text-n-blue-11 hover:underline"
              >
                <span
                  aria-hidden="true"
                  class="i-lucide-external-link size-3.5"
                />
                {{ t('AI_ASSISTANT.LEARNING.OPEN_CONVERSATION') }}
              </a>
            </div>
            <p class="m-0 break-words text-sm text-n-slate-12">
              {{ suggestion.suggested_instruction || suggestion.reason }}
            </p>
            <p
              v-if="suggestion.status === 'applied'"
              class="m-0 text-xs text-n-slate-9"
            >
              {{
                suggestion.destination === 'knowledge'
                  ? t('AI_ASSISTANT.LEARNING.ADDED_AS_KNOWLEDGE', {
                      name: suggestion.source_name,
                    })
                  : t('AI_ASSISTANT.LEARNING.ADDED_AS_INSTRUCTION')
              }}
            </p>
          </article>
        </div>
      </details>
    </div>

    <woot-confirm-modal
      ref="confirmDialog"
      :title="t('AI_ASSISTANT.LEARNING.CONFIRM_DISMISS.TITLE')"
      :description="t('AI_ASSISTANT.LEARNING.CONFIRM_DISMISS.DESCRIPTION')"
    />
  </section>
</template>
