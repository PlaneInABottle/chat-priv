<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import AiDataRetentionAPI from 'dashboard/api/aiDataRetention';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  kind: {
    type: String,
    required: true,
    validator: value => ['text', 'voice'].includes(value),
  },
});

const { t } = useI18n();
const cleanupDialogRef = ref(null);
const days = ref(30);
const savedDays = ref(30);
const allowedDays = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);
const isQueueing = ref(false);

const retentionCopy = computed(
  () =>
    ({
      text: {
        title: t('AI_DATA_RETENTION.TEXT.TITLE'),
        description: t('AI_DATA_RETENTION.TEXT.DESCRIPTION'),
      },
      voice: {
        title: t('AI_DATA_RETENTION.VOICE.TITLE'),
        description: t('AI_DATA_RETENTION.VOICE.DESCRIPTION'),
      },
    })[props.kind]
);
const isDirty = computed(() => days.value !== savedDays.value);

const loadPolicy = async () => {
  isLoading.value = true;
  try {
    const { data } = await AiDataRetentionAPI.get();
    days.value = data[props.kind].days;
    savedDays.value = data[props.kind].days;
    allowedDays.value = data.allowed_days;
  } catch {
    useAlert(t('AI_DATA_RETENTION.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const savePolicy = async () => {
  isSaving.value = true;
  try {
    const { data } = await AiDataRetentionAPI.updatePolicy(
      props.kind,
      days.value
    );
    days.value = data[props.kind].days;
    savedDays.value = data[props.kind].days;
    useAlert(t('AI_DATA_RETENTION.SAVE_SUCCESS'));
  } catch (error) {
    useAlert(error.response?.data?.error || t('AI_DATA_RETENTION.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const queueCleanup = async () => {
  isQueueing.value = true;
  try {
    await AiDataRetentionAPI.purge(props.kind);
    cleanupDialogRef.value?.close();
    useAlert(t('AI_DATA_RETENTION.CLEANUP_QUEUED'));
  } catch (error) {
    useAlert(
      error.response?.data?.error || t('AI_DATA_RETENTION.CLEANUP_ERROR')
    );
  } finally {
    isQueueing.value = false;
  }
};

onMounted(loadPolicy);
</script>

<template>
  <section class="flex max-w-3xl flex-col gap-8">
    <header>
      <h2 class="m-0 text-xl font-semibold text-n-slate-12">
        {{ retentionCopy.title }}
      </h2>
      <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
        {{ retentionCopy.description }}
      </p>
    </header>

    <div class="flex flex-col gap-3 border-b border-n-weak pb-8">
      <label class="flex max-w-sm flex-col gap-2 text-sm font-medium">
        {{ t('AI_DATA_RETENTION.DELETE_AFTER') }}
        <select
          v-model.number="days"
          class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal"
          :disabled="isLoading || isSaving"
        >
          <option v-for="option in allowedDays" :key="option" :value="option">
            {{ t('AI_DATA_RETENTION.DAYS', { count: option }) }}
          </option>
        </select>
      </label>
      <p class="m-0 text-xs leading-5 text-n-slate-10">
        {{ t('AI_DATA_RETENTION.CORE_DATA_NOTICE') }}
      </p>
      <div>
        <Button
          icon="i-lucide-save"
          :label="t('AI_DATA_RETENTION.SAVE')"
          :is-loading="isSaving"
          :disabled="isLoading || !isDirty"
          @click="savePolicy"
        />
      </div>
    </div>

    <div class="flex flex-col items-start gap-3">
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('AI_DATA_RETENTION.CLEANUP_TITLE') }}
      </h3>
      <p class="m-0 text-sm leading-6 text-n-slate-11">
        {{ t('AI_DATA_RETENTION.CLEANUP_DESCRIPTION', { days: savedDays }) }}
      </p>
      <Button
        icon="i-lucide-trash-2"
        color="ruby"
        variant="outline"
        :label="t('AI_DATA_RETENTION.CLEANUP')"
        :disabled="isLoading || isDirty"
        @click="cleanupDialogRef?.open()"
      />
    </div>
  </section>

  <Dialog
    ref="cleanupDialogRef"
    type="alert"
    :title="t('AI_DATA_RETENTION.CLEANUP_CONFIRM_TITLE')"
    :description="
      t('AI_DATA_RETENTION.CLEANUP_CONFIRM_DESCRIPTION', { days: savedDays })
    "
    :confirm-button-label="t('AI_DATA_RETENTION.CLEANUP_CONFIRM')"
    :cancel-button-label="t('AI_DATA_RETENTION.CANCEL')"
    :is-loading="isQueueing"
    @confirm="queueCleanup"
  />
</template>
