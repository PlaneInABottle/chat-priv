<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import VoiceAPI from 'dashboard/api/voice';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

const props = defineProps({
  voiceAgents: { type: Array, default: () => [] },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { getPlainText } = useMessageFormatter();
const calls = ref([]);
const isLoading = ref(false);
const showFilters = ref(false);
const filters = ref({
  status: '',
  handoff_status: '',
  voice_agent_id: '',
  phone: '',
  limit: 25,
});

const statusOptions = ['in_progress', 'completed', 'no_answer', 'failed'];
const handoffOptions = ['requested', 'accepted', 'none'];

const compactFilters = computed(() =>
  Object.fromEntries(
    Object.entries(filters.value).filter(
      ([, value]) => value !== '' && value !== null && value !== undefined
    )
  )
);

const fetchCalls = async () => {
  if (isLoading.value) return;

  isLoading.value = true;
  try {
    const response = await VoiceAPI.getCalls(compactFilters.value);
    calls.value = response.data || [];
  } catch {
    useAlert(t('VOICE_AI.CALL_ACTIVITY.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const applyFilters = async () => {
  await fetchCalls();
  showFilters.value = false;
};

const openConversation = call => {
  if (!call.conversation_id) return;

  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: call.conversation_id,
    },
  });
};

const formatDateTime = value =>
  new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));

const formatDuration = seconds => {
  if (!Number.isFinite(Number(seconds))) return '-';
  const value = Number(seconds);
  const minutes = Math.floor(value / 60);
  const remainder = value % 60;

  return minutes ? `${minutes}m ${remainder}s` : `${remainder}s`;
};

const optionLabel = (group, value) =>
  // The values are constrained by backend enums and the option arrays above.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`VOICE_AI.CALL_ACTIVITY.${group}.${value.toUpperCase()}`);

const outcomeAppearance = outcome => {
  if (outcome === 'failed') {
    return { icon: 'i-lucide-circle-x', classes: 'text-n-ruby-11' };
  }
  if (outcome === 'no_answer') {
    return { icon: 'i-lucide-phone-missed', classes: 'text-n-amber-11' };
  }
  if (outcome === 'human_handoff') {
    return { icon: 'i-lucide-user-round-check', classes: 'text-n-amber-11' };
  }
  if (outcome === 'completed') {
    return { icon: 'i-lucide-circle-check', classes: 'text-n-teal-11' };
  }

  return { icon: 'i-lucide-loader-circle', classes: 'text-n-blue-11' };
};

const callTitle = call =>
  call.conversation_id
    ? t('VOICE_AI.CALL_ACTIVITY.CONVERSATION', {
        id: call.conversation_id,
      })
    : t('VOICE_AI.CALL_ACTIVITY.CALL', { id: call.id });

const plainSummary = summary => getPlainText(summary);

onMounted(fetchCalls);
</script>

<template>
  <section class="flex min-w-0 flex-col gap-5">
    <header
      class="flex flex-col gap-4 border-b border-n-weak pb-5 md:flex-row md:items-start md:justify-between"
    >
      <div>
        <h2 class="m-0 text-heading-2 text-n-slate-12">
          {{ t('VOICE_AI.CALL_ACTIVITY.TITLE') }}
        </h2>
        <p class="mb-0 mt-1 max-w-3xl text-sm text-n-slate-11">
          {{ t('VOICE_AI.CALL_ACTIVITY.DESCRIPTION') }}
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <Button
          class="sm:hidden"
          icon="i-lucide-sliders-horizontal"
          variant="outline"
          color="slate"
          :label="t('VOICE_AI.CALL_ACTIVITY.FILTERS')"
          @click="showFilters = !showFilters"
        />
        <Button
          icon="i-lucide-refresh-cw"
          variant="outline"
          color="slate"
          :label="t('VOICE_AI.CALL_ACTIVITY.REFRESH')"
          :is-loading="isLoading"
          @click="fetchCalls"
        />
      </div>
    </header>

    <div
      class="grid grid-cols-1 gap-3 sm:!grid sm:grid-cols-2 xl:grid-cols-[160px_160px_200px_minmax(0,1fr)_120px]"
      :class="{ hidden: !showFilters }"
    >
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('VOICE_AI.CALL_ACTIVITY.STATUS_LABEL') }}
        <select
          v-model="filters.status"
          class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-sm text-n-slate-12"
        >
          <option value="">{{ t('VOICE_AI.CALL_ACTIVITY.ALL') }}</option>
          <option v-for="status in statusOptions" :key="status" :value="status">
            {{ optionLabel('STATUS', status) }}
          </option>
        </select>
      </label>

      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('VOICE_AI.CALL_ACTIVITY.HANDOFF_LABEL') }}
        <select
          v-model="filters.handoff_status"
          class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-sm text-n-slate-12"
        >
          <option value="">{{ t('VOICE_AI.CALL_ACTIVITY.ALL') }}</option>
          <option
            v-for="handoff in handoffOptions"
            :key="handoff"
            :value="handoff"
          >
            {{ optionLabel('HANDOFF', handoff) }}
          </option>
        </select>
      </label>

      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('VOICE_AI.CALL_ACTIVITY.ASSISTANT_LABEL') }}
        <select
          v-model="filters.voice_agent_id"
          class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-sm text-n-slate-12"
        >
          <option value="">{{ t('VOICE_AI.CALL_ACTIVITY.ALL') }}</option>
          <option
            v-for="agent in props.voiceAgents"
            :key="agent.id"
            :value="agent.id"
          >
            {{ agent.name }}
          </option>
        </select>
      </label>

      <Input
        v-model="filters.phone"
        :label="t('VOICE_AI.CALL_ACTIVITY.PHONE_LABEL')"
      />

      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('VOICE_AI.CALL_ACTIVITY.LIMIT_LABEL') }}
        <input
          v-model.number="filters.limit"
          type="number"
          min="1"
          max="100"
          class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-sm text-n-slate-12"
        />
      </label>
    </div>

    <div class="justify-end sm:flex" :class="showFilters ? 'flex' : 'hidden'">
      <Button
        icon="i-lucide-search"
        :label="t('VOICE_AI.CALL_ACTIVITY.APPLY')"
        :is-loading="isLoading"
        @click="applyFilters"
      />
    </div>

    <div
      v-if="isLoading && !calls.length"
      class="py-12 text-center text-sm text-n-slate-10"
    >
      {{ t('VOICE_AI.CALL_ACTIVITY.LOADING') }}
    </div>
    <div
      v-else-if="!calls.length"
      class="border-y border-n-weak py-12 text-center text-sm text-n-slate-10"
    >
      {{ t('VOICE_AI.CALL_ACTIVITY.EMPTY') }}
    </div>
    <div v-else class="flex min-w-0 flex-col border-y border-n-weak">
      <article
        v-for="call in calls"
        :key="call.id"
        class="flex min-w-0 flex-col gap-4 border-b border-n-weak py-5 last:border-b-0"
      >
        <div class="flex min-w-0 items-start justify-between gap-4">
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                {{ callTitle(call) }}
              </h3>
              <span
                class="inline-flex items-center gap-1 text-xs font-medium"
                :class="outcomeAppearance(call.outcome).classes"
              >
                <span
                  aria-hidden="true"
                  class="size-3.5 flex-shrink-0"
                  :class="outcomeAppearance(call.outcome).icon"
                />
                {{ optionLabel('OUTCOME', call.outcome) }}
              </span>
            </div>
            <p class="mb-0 mt-1 text-xs text-n-slate-10">
              {{ formatDateTime(call.started_at) }}
              <span aria-hidden="true">
                {{ t('VOICE_AI.CALL_ACTIVITY.METADATA_SEPARATOR') }}
              </span>
              {{ call.inbox?.name }}
              <template v-if="call.voice_agent?.name">
                <span aria-hidden="true">
                  {{ t('VOICE_AI.CALL_ACTIVITY.METADATA_SEPARATOR') }}
                </span>
                {{ call.voice_agent.name }}
              </template>
            </p>
          </div>
          <Button
            v-if="call.conversation_id"
            class="hidden sm:flex"
            icon="i-lucide-external-link"
            size="sm"
            variant="ghost"
            color="slate"
            :label="t('VOICE_AI.CALL_ACTIVITY.OPEN_CONVERSATION')"
            @click="openConversation(call)"
          />
          <Button
            v-if="call.conversation_id"
            v-tooltip="t('VOICE_AI.CALL_ACTIVITY.OPEN_CONVERSATION')"
            class="sm:hidden"
            icon="i-lucide-external-link"
            size="sm"
            variant="ghost"
            color="slate"
            :aria-label="t('VOICE_AI.CALL_ACTIVITY.OPEN_CONVERSATION')"
            @click="openConversation(call)"
          />
        </div>

        <p v-if="call.summary" class="m-0 break-words text-sm text-n-slate-12">
          {{ plainSummary(call.summary) }}
        </p>
        <p v-else class="m-0 text-sm text-n-slate-10">
          {{ t('VOICE_AI.CALL_ACTIVITY.NO_SUMMARY') }}
        </p>

        <dl
          class="grid grid-cols-2 gap-x-5 gap-y-3 text-sm sm:grid-cols-3 xl:grid-cols-6"
        >
          <div>
            <dt class="text-xs text-n-slate-10">
              {{ t('VOICE_AI.CALL_ACTIVITY.PHONE') }}
            </dt>
            <dd class="m-0 mt-1 break-words text-n-slate-12">
              {{ call.from_number || '-' }}
            </dd>
          </div>
          <div>
            <dt class="text-xs text-n-slate-10">
              {{ t('VOICE_AI.CALL_ACTIVITY.DURATION') }}
            </dt>
            <dd class="m-0 mt-1 text-n-slate-12">
              {{ formatDuration(call.duration_seconds) }}
            </dd>
          </div>
          <div>
            <dt class="text-xs text-n-slate-10">
              {{ t('VOICE_AI.CALL_ACTIVITY.TRANSCRIPT') }}
            </dt>
            <dd class="m-0 mt-1 text-n-slate-12">
              {{ call.transcript_count }}
            </dd>
          </div>
          <div>
            <dt class="text-xs text-n-slate-10">
              {{ t('VOICE_AI.CALL_ACTIVITY.ACTIONS') }}
            </dt>
            <dd class="m-0 mt-1 text-n-slate-12">
              {{ call.action_count }}
              <span v-if="call.action_error_count" class="text-n-ruby-11">
                {{
                  t('VOICE_AI.CALL_ACTIVITY.ACTION_ERRORS', {
                    count: call.action_error_count,
                  })
                }}
              </span>
            </dd>
          </div>
          <div>
            <dt class="text-xs text-n-slate-10">
              {{ t('VOICE_AI.CALL_ACTIVITY.HANDOFF_METRIC') }}
            </dt>
            <dd class="m-0 mt-1 text-n-slate-12">
              {{ optionLabel('HANDOFF', call.handoff_status) }}
            </dd>
          </div>
          <div>
            <dt class="text-xs text-n-slate-10">
              {{ t('VOICE_AI.CALL_ACTIVITY.RECORDING_METRIC') }}
            </dt>
            <dd class="m-0 mt-1 text-n-slate-12">
              {{ optionLabel('RECORDING', call.recording_status) }}
            </dd>
          </div>
        </dl>
      </article>
    </div>
  </section>
</template>
