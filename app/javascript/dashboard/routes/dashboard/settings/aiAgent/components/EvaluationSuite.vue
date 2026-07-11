<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import AiAgentEvaluationsAPI from 'dashboard/api/aiAgentEvaluations';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  aiAgentId: { type: Number, required: true },
  hasUnsavedInstructions: { type: Boolean, default: false },
});

const { t } = useI18n();
const evaluationCases = ref([]);
const evaluationRuns = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);
const isStartingRun = ref(false);
const showForm = ref(false);
const editingCaseId = ref(null);
const confirmDialog = ref(null);
let pollTimer;

const emptyForm = () => ({
  name: '',
  customer_message: '',
  success_criteria: '',
});
const form = ref(emptyForm());

const api = computed(() => new AiAgentEvaluationsAPI(props.aiAgentId));
const latestRun = computed(() => evaluationRuns.value[0] || null);
const isRunActive = computed(() =>
  ['pending', 'running'].includes(latestRun.value?.status)
);
const isFormValid = computed(
  () =>
    form.value.name.trim() &&
    form.value.customer_message.trim() &&
    form.value.success_criteria.trim()
);

const runSummary = computed(() => {
  const run = latestRun.value;
  if (!run) return null;
  if (['pending', 'running'].includes(run.status)) {
    return {
      icon: 'i-lucide-loader-circle animate-spin',
      classes: 'text-n-blue-11',
      label: t('AI_ASSISTANT.EVALUATIONS.RUN.RUNNING'),
    };
  }
  if (run.status === 'failed') {
    return {
      icon: 'i-lucide-circle-alert',
      classes: 'text-n-ruby-11',
      label: run.error_message || t('AI_ASSISTANT.EVALUATIONS.RUN.FAILED'),
    };
  }

  return {
    icon:
      run.passed_count === run.total_count
        ? 'i-lucide-circle-check'
        : 'i-lucide-circle-dot-dashed',
    classes:
      run.passed_count === run.total_count
        ? 'text-n-teal-11'
        : 'text-n-amber-11',
    label: t('AI_ASSISTANT.EVALUATIONS.RUN.SUMMARY', {
      passed: run.passed_count,
      total: run.total_count,
    }),
  };
});

let refreshRun;

function schedulePoll() {
  window.clearTimeout(pollTimer);
  if (isRunActive.value) {
    pollTimer = window.setTimeout(refreshRun, 1500);
  }
}

const loadEvaluations = async () => {
  isLoading.value = true;
  try {
    const [casesResponse, runsResponse] = await Promise.all([
      api.value.get(),
      api.value.getRuns(),
    ]);
    evaluationCases.value = casesResponse.data;
    evaluationRuns.value = runsResponse.data;
    schedulePoll();
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) || t('AI_ASSISTANT.EVALUATIONS.ERROR.LOAD')
    );
  } finally {
    isLoading.value = false;
  }
};

refreshRun = async () => {
  if (!latestRun.value) return;
  try {
    const response = await api.value.getRun(latestRun.value.id);
    evaluationRuns.value = [
      response.data,
      ...evaluationRuns.value.filter(run => run.id !== response.data.id),
    ];
    schedulePoll();
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) ||
        t('AI_ASSISTANT.EVALUATIONS.ERROR.REFRESH')
    );
  }
};

const resetForm = () => {
  form.value = emptyForm();
  editingCaseId.value = null;
  showForm.value = false;
};

const openCreateForm = () => {
  form.value = emptyForm();
  editingCaseId.value = null;
  showForm.value = true;
};

const openEditForm = evaluationCase => {
  form.value = {
    name: evaluationCase.name,
    customer_message: evaluationCase.customer_message,
    success_criteria: evaluationCase.success_criteria,
  };
  editingCaseId.value = evaluationCase.id;
  showForm.value = true;
};

const saveCase = async () => {
  if (!isFormValid.value) return;
  isSaving.value = true;
  const payload = {
    name: form.value.name.trim(),
    customer_message: form.value.customer_message.trim(),
    success_criteria: form.value.success_criteria.trim(),
  };

  try {
    const response = editingCaseId.value
      ? await api.value.updateCase(editingCaseId.value, payload)
      : await api.value.create(payload);
    const existingIndex = evaluationCases.value.findIndex(
      item => item.id === response.data.id
    );
    if (existingIndex >= 0) {
      evaluationCases.value.splice(existingIndex, 1, response.data);
    } else {
      evaluationCases.value.push(response.data);
    }
    resetForm();
    useAlert(t('AI_ASSISTANT.EVALUATIONS.SAVED'));
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) || t('AI_ASSISTANT.EVALUATIONS.ERROR.SAVE')
    );
  } finally {
    isSaving.value = false;
  }
};

const deleteCase = async evaluationCase => {
  const confirmed = await confirmDialog.value.showConfirmation();
  if (!confirmed) return;

  try {
    await api.value.deleteCase(evaluationCase.id);
    evaluationCases.value = evaluationCases.value.filter(
      item => item.id !== evaluationCase.id
    );
    useAlert(t('AI_ASSISTANT.EVALUATIONS.DELETED'));
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) || t('AI_ASSISTANT.EVALUATIONS.ERROR.DELETE')
    );
  }
};

const startRun = async () => {
  if (props.hasUnsavedInstructions) return;

  isStartingRun.value = true;
  try {
    const response = await api.value.createRun();
    evaluationRuns.value = [response.data, ...evaluationRuns.value];
    schedulePoll();
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) || t('AI_ASSISTANT.EVALUATIONS.ERROR.RUN')
    );
  } finally {
    isStartingRun.value = false;
  }
};

const resultForCase = evaluationCase => {
  const run = latestRun.value;
  if (!run) return null;

  return run.results.find(
    result => result.evaluation_case_id === evaluationCase.id
  );
};

const resultAppearance = (result, caseChangedSinceRun) => {
  if (caseChangedSinceRun) {
    return {
      icon: 'i-lucide-history',
      classes: 'text-n-amber-11',
      label: t('AI_ASSISTANT.EVALUATIONS.RESULT.CHANGED'),
    };
  }
  if (result && !latestRun.value?.current_draft) {
    return {
      icon: 'i-lucide-history',
      classes: 'text-n-amber-11',
      label: t('AI_ASSISTANT.EVALUATIONS.RESULT.OLDER_DRAFT'),
    };
  }
  if (!result || result.status === 'pending') {
    return {
      icon: 'i-lucide-clock-3',
      classes: 'text-n-slate-10',
      label: t('AI_ASSISTANT.EVALUATIONS.RESULT.NOT_RUN'),
    };
  }
  if (result.status === 'failed' || !result.passed) {
    return {
      icon: 'i-lucide-circle-x',
      classes: 'text-n-ruby-11',
      label: t('AI_ASSISTANT.EVALUATIONS.RESULT.FAILED'),
    };
  }

  return {
    icon: 'i-lucide-circle-check',
    classes: 'text-n-teal-11',
    label: t('AI_ASSISTANT.EVALUATIONS.RESULT.PASSED'),
  };
};

const scenarioRows = computed(() =>
  evaluationCases.value.map(evaluationCase => {
    const result = resultForCase(evaluationCase);
    const caseChangedSinceRun = Boolean(
      result &&
        new Date(evaluationCase.updated_at) >
          new Date(latestRun.value.created_at)
    );
    return {
      evaluationCase,
      result: caseChangedSinceRun ? null : result,
      appearance: resultAppearance(result, caseChangedSinceRun),
    };
  })
);

onMounted(loadEvaluations);
onBeforeUnmount(() => window.clearTimeout(pollTimer));
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-6"
    aria-labelledby="evaluation-title"
  >
    <header
      class="flex flex-col gap-4 border-b border-n-weak pb-5 sm:flex-row sm:items-start sm:justify-between"
    >
      <div class="min-w-0">
        <h2
          id="evaluation-title"
          class="m-0 text-xl font-semibold text-n-slate-12"
        >
          {{ t('AI_ASSISTANT.EVALUATIONS.TITLE') }}
        </h2>
        <p class="mb-0 mt-1 max-w-2xl text-sm text-n-slate-11">
          {{ t('AI_ASSISTANT.EVALUATIONS.DESCRIPTION') }}
        </p>
      </div>
      <div class="flex flex-shrink-0 flex-wrap items-center gap-2">
        <Button
          v-if="evaluationCases.length < 20"
          icon="i-lucide-plus"
          variant="outline"
          color="slate"
          :label="t('AI_ASSISTANT.EVALUATIONS.ADD')"
          @click="openCreateForm"
        />
        <Button
          icon="i-lucide-play"
          :label="t('AI_ASSISTANT.EVALUATIONS.RUN.ACTION')"
          :is-loading="isStartingRun"
          :disabled="
            !evaluationCases.length || isRunActive || hasUnsavedInstructions
          "
          @click="startRun"
        />
      </div>
    </header>

    <div
      v-if="latestRun"
      class="flex flex-col gap-2 border-b border-n-weak pb-5 text-sm sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex min-w-0 items-start gap-2" :class="runSummary.classes">
        <span
          aria-hidden="true"
          class="mt-0.5 size-4 flex-shrink-0"
          :class="runSummary.icon"
        />
        <span>{{ runSummary.label }}</span>
      </div>
      <p
        v-if="!latestRun.current_draft"
        class="m-0 flex items-center gap-1.5 text-xs text-n-amber-11"
      >
        <span
          aria-hidden="true"
          class="i-lucide-history size-3.5 flex-shrink-0"
        />
        {{ t('AI_ASSISTANT.EVALUATIONS.RUN.OLDER_DRAFT') }}
      </p>
    </div>

    <form
      v-if="showForm"
      class="grid grid-cols-1 gap-4 border-b border-n-weak pb-6"
      @submit.prevent="saveCase"
    >
      <label
        class="flex max-w-2xl flex-col gap-1.5 text-sm font-medium text-n-slate-12"
      >
        {{ t('AI_ASSISTANT.EVALUATIONS.FORM.NAME') }}
        <input
          v-model="form.name"
          name="evaluation-name"
          autocomplete="off"
          maxlength="100"
          class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal outline-none focus-visible:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/20"
          :placeholder="t('AI_ASSISTANT.EVALUATIONS.FORM.NAME_PLACEHOLDER')"
        />
      </label>
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <label
          class="flex flex-col gap-1.5 text-sm font-medium text-n-slate-12"
        >
          {{ t('AI_ASSISTANT.EVALUATIONS.FORM.MESSAGE') }}
          <textarea
            v-model="form.customer_message"
            name="evaluation-customer-message"
            autocomplete="off"
            maxlength="5000"
            rows="4"
            class="min-h-28 resize-y rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 font-normal outline-none focus-visible:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/20"
            :placeholder="
              t('AI_ASSISTANT.EVALUATIONS.FORM.MESSAGE_PLACEHOLDER')
            "
          />
          <span class="font-normal text-n-slate-10">
            {{ t('AI_ASSISTANT.EVALUATIONS.FORM.MESSAGE_HELP') }}
          </span>
        </label>
        <label
          class="flex flex-col gap-1.5 text-sm font-medium text-n-slate-12"
        >
          {{ t('AI_ASSISTANT.EVALUATIONS.FORM.CRITERIA') }}
          <textarea
            v-model="form.success_criteria"
            name="evaluation-success-criteria"
            autocomplete="off"
            maxlength="5000"
            rows="4"
            class="min-h-28 resize-y rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 font-normal outline-none focus-visible:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/20"
            :placeholder="
              t('AI_ASSISTANT.EVALUATIONS.FORM.CRITERIA_PLACEHOLDER')
            "
          />
          <span class="font-normal text-n-slate-10">
            {{ t('AI_ASSISTANT.EVALUATIONS.FORM.CRITERIA_HELP') }}
          </span>
        </label>
      </div>
      <div class="flex justify-end gap-2">
        <Button
          type="button"
          variant="ghost"
          color="slate"
          :label="t('AI_ASSISTANT.EVALUATIONS.FORM.CANCEL')"
          :disabled="isSaving"
          @click="resetForm"
        />
        <Button
          type="submit"
          :label="t('AI_ASSISTANT.EVALUATIONS.FORM.SAVE')"
          :is-loading="isSaving"
          :disabled="!isFormValid"
        />
      </div>
    </form>

    <div v-if="isLoading" class="py-12 text-center text-sm text-n-slate-10">
      {{ t('AI_ASSISTANT.EVALUATIONS.LOADING') }}
    </div>
    <div
      v-else-if="!evaluationCases.length"
      class="border-y border-n-weak py-12 text-center"
    >
      <span
        aria-hidden="true"
        class="i-lucide-list-checks mx-auto block size-6 text-n-slate-9"
      />
      <h3 class="mb-0 mt-3 text-sm font-semibold text-n-slate-12">
        {{ t('AI_ASSISTANT.EVALUATIONS.EMPTY.TITLE') }}
      </h3>
      <p class="mx-auto mb-0 mt-1 max-w-lg text-sm text-n-slate-10">
        {{ t('AI_ASSISTANT.EVALUATIONS.EMPTY.DESCRIPTION') }}
      </p>
    </div>
    <div v-else class="flex flex-col border-y border-n-weak">
      <article
        v-for="row in scenarioRows"
        :key="row.evaluationCase.id"
        class="flex min-w-0 flex-col gap-4 border-b border-n-weak px-1 py-5 last:border-b-0"
      >
        <div class="flex min-w-0 items-start justify-between gap-4">
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="m-0 break-words text-sm font-semibold text-n-slate-12">
                {{ row.evaluationCase.name }}
              </h3>
              <span
                class="inline-flex items-center gap-1 text-xs font-medium"
                :class="row.appearance.classes"
              >
                <span
                  aria-hidden="true"
                  class="size-3.5 flex-shrink-0"
                  :class="row.appearance.icon"
                />
                {{ row.appearance.label }}
              </span>
            </div>
            <p class="mb-0 mt-2 break-words text-sm text-n-slate-12">
              {{ row.evaluationCase.customer_message }}
            </p>
            <p class="mb-0 mt-1 break-words text-xs text-n-slate-10">
              <span class="font-medium text-n-slate-11">
                {{ t('AI_ASSISTANT.EVALUATIONS.CRITERIA_LABEL') }}
              </span>
              {{ row.evaluationCase.success_criteria }}
            </p>
          </div>
          <div class="flex flex-shrink-0 items-center gap-1">
            <Button
              v-tooltip="t('AI_ASSISTANT.EVALUATIONS.EDIT')"
              icon="i-lucide-pencil"
              size="sm"
              variant="ghost"
              color="slate"
              :aria-label="t('AI_ASSISTANT.EVALUATIONS.EDIT')"
              @click="openEditForm(row.evaluationCase)"
            />
            <Button
              v-tooltip="t('AI_ASSISTANT.EVALUATIONS.DELETE')"
              icon="i-lucide-trash-2"
              size="sm"
              variant="ghost"
              color="ruby"
              :aria-label="t('AI_ASSISTANT.EVALUATIONS.DELETE')"
              @click="deleteCase(row.evaluationCase)"
            />
          </div>
        </div>

        <div
          v-if="row.result?.assistant_response || row.result?.reason"
          class="grid min-w-0 grid-cols-1 gap-3 border-l-2 border-n-weak pl-4 lg:grid-cols-2"
        >
          <div v-if="row.result.assistant_response" class="min-w-0">
            <p class="m-0 text-xs font-medium text-n-slate-10">
              {{ t('AI_ASSISTANT.EVALUATIONS.RESULT.ANSWER') }}
            </p>
            <p
              class="mb-0 mt-1 whitespace-pre-wrap break-words text-sm text-n-slate-12"
            >
              {{ row.result.assistant_response }}
            </p>
          </div>
          <div v-if="row.result.reason" class="min-w-0">
            <p class="m-0 text-xs font-medium text-n-slate-10">
              {{ t('AI_ASSISTANT.EVALUATIONS.RESULT.REASON') }}
            </p>
            <p class="mb-0 mt-1 break-words text-sm text-n-slate-11">
              {{ row.result.reason }}
            </p>
          </div>
        </div>
      </article>
    </div>

    <woot-confirm-modal
      ref="confirmDialog"
      :title="t('AI_ASSISTANT.EVALUATIONS.CONFIRM_DELETE.TITLE')"
      :description="t('AI_ASSISTANT.EVALUATIONS.CONFIRM_DELETE.DESCRIPTION')"
    />
  </section>
</template>
