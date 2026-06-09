<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import VoiceAPI from 'dashboard/api/voice';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useLivekitVoiceSession } from 'dashboard/composables/useLivekitVoiceSession';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const DEFAULT_GREETING = 'Merhaba, size nasil yardimci olabilirim?';
const TERMINAL_CALL_STATUSES = [
  'completed',
  'no-answer',
  'no_answer',
  'failed',
];

const store = useStore();
const { t } = useI18n();

const settings = ref([]);
const selectedInboxId = ref('');
const selectedAiAgentId = ref('');
const selectedFallbackTeamId = ref('');
const greeting = ref(DEFAULT_GREETING);
const instructions = ref('');
const callerName = ref('Test caller');
const callerNumber = ref('+900000000000');
const currentCall = ref(null);
const isLoading = ref(false);
const isSaving = ref(false);
const isCreatingCall = ref(false);
const isEnding = ref(false);
const isRefreshing = ref(false);
const refreshTimer = ref(null);
const {
  remoteAudioRef,
  sessionStatus,
  sessionError,
  activeParticipantType,
  isJoining,
  isMuted,
  isConnected,
  joinRoom,
  disconnectRoom,
  toggleMute,
} = useLivekitVoiceSession({ call: currentCall });

const inboxes = useMapGetter('inboxes/getInboxes');
const aiAgents = useMapGetter('aiAgent/getAiAgents');
const teams = useMapGetter('teams/getTeams');

const apiInboxes = computed(() =>
  (inboxes.value || []).filter(inbox => inbox.channel_type === INBOX_TYPES.API)
);

const selectedSetting = computed(() =>
  settings.value.find(
    setting => Number(setting.inbox_id) === Number(selectedInboxId.value)
  )
);

const canSave = computed(() => Boolean(selectedInboxId.value));
const currentCallStatus = computed(() => currentCall.value?.status || '');
const isCurrentCallTerminal = computed(() =>
  TERMINAL_CALL_STATUSES.includes(currentCallStatus.value)
);
const hasCall = computed(() => Boolean(currentCall.value?.id));
const hasActiveTestCall = computed(
  () => hasCall.value && !isCurrentCallTerminal.value
);
const canEditSetup = computed(() => !hasActiveTestCall.value);
const canStartTest = computed(
  () =>
    Boolean(selectedInboxId.value) &&
    !isCreatingCall.value &&
    !hasActiveTestCall.value
);
const canJoin = computed(
  () =>
    Boolean(currentCall.value?.id) &&
    !isCurrentCallTerminal.value &&
    !isJoining.value
);
const canUseLiveControls = computed(
  () => hasCall.value && !isCurrentCallTerminal.value
);
const sessionStatusLabels = computed(() => ({
  disconnected: t('VOICE_AI.SESSION.DISCONNECTED'),
  connecting: t('VOICE_AI.SESSION.CONNECTING'),
  connected: t('VOICE_AI.SESSION.CONNECTED'),
  failed: t('VOICE_AI.SESSION.FAILED'),
}));

const transcriptSegments = computed(
  () => currentCall.value?.transcript_segments || []
);
const toolEvents = computed(() => currentCall.value?.tool_events || []);
const timelineEvents = computed(() => {
  const transcriptItems = transcriptSegments.value.map(segment => ({
    ...segment,
    timelineType: 'transcript',
    timelineId: `transcript-${segment.id}`,
    sortAt: segment.created_at,
  }));
  const toolItems = toolEvents.value.map(event => ({
    ...event,
    timelineType: 'tool',
    timelineId: `tool-${event.id || event.created_at}`,
    sortAt: event.created_at,
  }));

  return [...transcriptItems, ...toolItems].sort((a, b) => {
    const first = new Date(a.sortAt || 0).getTime();
    const second = new Date(b.sortAt || 0).getTime();
    return first - second;
  });
});

const sessionStatusLabel = computed(() => {
  return sessionStatusLabels.value[sessionStatus.value] || sessionStatus.value;
});
const callStatusLabel = computed(() => {
  return currentCallStatus.value || t('VOICE_AI.SESSION.NOT_STARTED');
});

const toolStatusClass = status => {
  if (status === 'executed') return 'text-n-teal-11 bg-n-teal-3';
  if (status === 'error' || status === 'rejected') {
    return 'text-n-ruby-11 bg-n-ruby-3';
  }
  return 'text-n-slate-11 bg-n-alpha-2';
};

const formatJson = value => JSON.stringify(value || {}, null, 2);

const settingPayload = () => ({
  inbox_id: selectedInboxId.value,
  ai_agent_id: selectedAiAgentId.value || null,
  fallback_team_id: selectedFallbackTeamId.value || null,
  greeting: greeting.value,
  instructions: instructions.value,
  status: 'test_only',
});

const loadData = async () => {
  isLoading.value = true;
  try {
    await Promise.all([
      store.dispatch('inboxes/get'),
      store.dispatch('aiAgent/get'),
      store.dispatch('teams/get'),
    ]);
    const response = await VoiceAPI.getSettings();
    settings.value = response.data?.payload || [];
    if (!selectedInboxId.value && apiInboxes.value.length) {
      selectedInboxId.value = apiInboxes.value[0].id;
    }
  } catch (error) {
    useAlert(t('VOICE_AI.SETUP.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const syncFormFromSetting = setting => {
  if (!setting) {
    selectedAiAgentId.value = aiAgents.value[0]?.id || '';
    selectedFallbackTeamId.value = '';
    greeting.value = DEFAULT_GREETING;
    instructions.value = '';
    return;
  }

  selectedAiAgentId.value = setting.ai_agent_id || '';
  selectedFallbackTeamId.value = setting.fallback_team_id || '';
  greeting.value = setting.greeting || DEFAULT_GREETING;
  instructions.value = setting.instructions || '';
};

const saveSettings = async ({ silent = false } = {}) => {
  if (!canSave.value) return null;

  isSaving.value = true;
  try {
    const existing = selectedSetting.value;
    const response = existing
      ? await VoiceAPI.updateSetting(existing.id, settingPayload())
      : await VoiceAPI.createSetting(settingPayload());

    const saved = response.data;
    settings.value = [
      ...settings.value.filter(setting => setting.id !== saved.id),
      saved,
    ];
    if (!silent) useAlert(t('VOICE_AI.SETUP.SAVE_SUCCESS'));
    return saved;
  } catch (error) {
    if (!silent) useAlert(t('VOICE_AI.SETUP.SAVE_ERROR'));
    throw error;
  } finally {
    isSaving.value = false;
  }
};

const createTestCall = async () => {
  if (!canStartTest.value) return;

  isCreatingCall.value = true;
  try {
    await saveSettings({ silent: true });
    const response = await VoiceAPI.createTestCall({
      inbox_id: selectedInboxId.value,
      caller_name: callerName.value,
      caller_number: callerNumber.value,
    });
    currentCall.value = response.data;
    disconnectRoom();
    useAlert(t('VOICE_AI.SETUP.START_SUCCESS'));
  } catch (error) {
    useAlert(error.response?.data?.error || t('VOICE_AI.SETUP.START_ERROR'));
  } finally {
    isCreatingCall.value = false;
  }
};

const refreshCall = async () => {
  if (!currentCall.value?.id || isRefreshing.value) return;

  isRefreshing.value = true;
  try {
    const response = await VoiceAPI.getCall(currentCall.value.id);
    currentCall.value = response.data;
  } finally {
    isRefreshing.value = false;
  }
};

const stopRefreshPolling = () => {
  if (!refreshTimer.value) return;

  clearInterval(refreshTimer.value);
  refreshTimer.value = null;
};

const startRefreshPolling = () => {
  stopRefreshPolling();

  const scheduleNext = async () => {
    if (!refreshTimer.value) return;
    await refreshCall();
    if (refreshTimer.value) {
      refreshTimer.value = setTimeout(scheduleNext, 4000);
    }
  };

  refreshTimer.value = setTimeout(scheduleNext, 4000);
};

const endCall = async () => {
  if (!canUseLiveControls.value || isEnding.value) return;

  isEnding.value = true;
  try {
    const response = await VoiceAPI.endCall(currentCall.value.id, {
      end_reason: 'browser_test_ended',
    });
    currentCall.value = response.data;
    disconnectRoom();
    useAlert(t('VOICE_AI.SESSION.END_SUCCESS'));
  } catch {
    useAlert(t('VOICE_AI.SESSION.ACTION_ERROR'));
  } finally {
    isEnding.value = false;
  }
};

watch(selectedInboxId, () => {
  syncFormFromSetting(selectedSetting.value);
});

watch(hasActiveTestCall, isActive => {
  if (isActive) {
    startRefreshPolling();
    return;
  }

  stopRefreshPolling();
});

onMounted(loadData);
onBeforeUnmount(stopRefreshPolling);
</script>

<template>
  <SettingsLayout :is-loading="isLoading">
    <template #header>
      <BaseSettingsHeader
        :title="t('VOICE_AI.HEADER')"
        :description="t('VOICE_AI.DESCRIPTION')"
        feature-name="voice_ai"
      />
    </template>

    <template #body>
      <div class="grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_360px] gap-6">
        <section
          class="rounded-xl border border-n-weak bg-n-solid-1 p-5 flex flex-col gap-5"
        >
          <div>
            <h2 class="text-heading-2 text-n-slate-12">
              {{ t('VOICE_AI.SETUP.TITLE') }}
            </h2>
            <p class="mb-0 mt-1 text-sm text-n-slate-11">
              {{ t('VOICE_AI.SETUP.DESCRIPTION') }}
            </p>
          </div>

          <div v-if="!apiInboxes.length" class="text-sm text-n-ruby-9">
            {{ t('VOICE_AI.SETUP.NO_API_INBOX') }}
          </div>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <label class="flex flex-col gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('VOICE_AI.SETUP.INBOX') }}
              </span>
              <select
                v-model="selectedInboxId"
                :disabled="!canEditSetup"
                class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <option value="" disabled>
                  {{ t('VOICE_AI.SETUP.INBOX') }}
                </option>
                <option
                  v-for="inbox in apiInboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
                  {{ inbox.name }}
                </option>
              </select>
            </label>

            <label class="flex flex-col gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('VOICE_AI.SETUP.AI_AGENT') }}
              </span>
              <select
                v-model="selectedAiAgentId"
                :disabled="!canEditSetup"
                class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <option value="">
                  {{ t('VOICE_AI.SETUP.NONE') }}
                </option>
                <option
                  v-for="agent in aiAgents"
                  :key="agent.id"
                  :value="agent.id"
                >
                  {{ agent.name }}
                </option>
              </select>
            </label>

            <label class="flex flex-col gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('VOICE_AI.SETUP.FALLBACK_TEAM') }}
              </span>
              <select
                v-model="selectedFallbackTeamId"
                :disabled="!canEditSetup"
                class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <option value="">
                  {{ t('VOICE_AI.SETUP.NONE') }}
                </option>
                <option v-for="team in teams" :key="team.id" :value="team.id">
                  {{ team.name }}
                </option>
              </select>
            </label>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Input
              v-model="greeting"
              :label="t('VOICE_AI.SETUP.GREETING')"
              :disabled="!canEditSetup"
            />
            <Input
              v-model="callerName"
              :label="t('VOICE_AI.SETUP.CALLER_NAME')"
              :disabled="!canEditSetup"
            />
            <Input
              v-model="callerNumber"
              :label="t('VOICE_AI.SETUP.CALLER_NUMBER')"
              :disabled="!canEditSetup"
            />
          </div>

          <label class="flex flex-col gap-1">
            <span class="text-heading-3 text-n-slate-12">
              {{ t('VOICE_AI.SETUP.INSTRUCTIONS') }}
            </span>
            <textarea
              v-model="instructions"
              rows="6"
              :disabled="!canEditSetup"
              class="rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 resize-y disabled:cursor-not-allowed disabled:opacity-50"
            />
          </label>

          <div class="flex flex-wrap gap-3">
            <Button
              :label="t('VOICE_AI.SETUP.SAVE')"
              icon="i-lucide-save"
              variant="outline"
              color="slate"
              :disabled="!canSave || !canEditSetup"
              :is-loading="isSaving"
              @click="saveSettings"
            />
            <Button
              :label="t('VOICE_AI.SETUP.START_TEST')"
              icon="i-lucide-phone-call"
              :disabled="!canStartTest"
              :is-loading="isCreatingCall"
              @click="createTestCall"
            />
          </div>
        </section>

        <aside
          class="rounded-xl border border-n-weak bg-n-solid-1 p-5 flex flex-col gap-4"
        >
          <div>
            <h2 class="text-heading-2 text-n-slate-12">
              {{ t('VOICE_AI.SESSION.TITLE') }}
            </h2>
            <p class="mb-0 mt-1 text-sm text-n-slate-11">
              {{
                hasCall
                  ? currentCall.livekit_room_name
                  : t('VOICE_AI.SESSION.NOT_STARTED')
              }}
            </p>
          </div>

          <dl
            class="grid grid-cols-[96px_minmax(0,1fr)] gap-x-3 gap-y-2 text-sm"
          >
            <dt class="text-n-slate-11">
              {{ t('VOICE_AI.SESSION.CALL_STATUS') }}
            </dt>
            <dd class="capitalize text-n-slate-12">{{ callStatusLabel }}</dd>
            <dt class="text-n-slate-11">
              {{ t('VOICE_AI.SESSION.BROWSER_STATUS') }}
            </dt>
            <dd class="text-n-slate-12">{{ sessionStatusLabel }}</dd>
            <dt class="text-n-slate-11">{{ t('VOICE_AI.SESSION.ROOM') }}</dt>
            <dd class="truncate text-n-slate-12">
              {{ currentCall?.livekit_room_name || '-' }}
            </dd>
          </dl>

          <p v-if="sessionError" class="mb-0 text-sm text-n-ruby-9">
            {{ sessionError }}
          </p>

          <div ref="remoteAudioRef" class="hidden" />

          <div class="grid grid-cols-1 gap-2">
            <Button
              :label="t('VOICE_AI.SESSION.JOIN_CALLER')"
              icon="i-lucide-phone"
              :disabled="!canJoin || isConnected"
              :is-loading="isJoining && activeParticipantType === 'caller'"
              @click="joinRoom('caller')"
            />
            <Button
              :label="
                isMuted
                  ? t('VOICE_AI.SESSION.UNMUTE')
                  : t('VOICE_AI.SESSION.MUTE')
              "
              icon="i-lucide-mic"
              variant="outline"
              color="slate"
              :disabled="!isConnected"
              @click="toggleMute"
            />
            <Button
              :label="t('VOICE_AI.SESSION.DISCONNECT')"
              icon="i-lucide-phone-off"
              variant="outline"
              color="ruby"
              :disabled="!isConnected"
              @click="disconnectRoom"
            />
            <Button
              :label="t('VOICE_AI.SESSION.END_CALL')"
              icon="i-lucide-circle-stop"
              variant="outline"
              color="ruby"
              :disabled="!canUseLiveControls || isEnding"
              :is-loading="isEnding"
              @click="endCall"
            />
          </div>

          <div class="h-px bg-n-weak" />

          <div class="grid grid-cols-1 gap-2">
            <Button
              :label="t('VOICE_AI.SESSION.REFRESH')"
              icon="i-lucide-refresh-cw"
              variant="outline"
              color="slate"
              :disabled="!hasCall"
              :is-loading="isRefreshing"
              @click="refreshCall"
            />
          </div>
        </aside>

        <section
          class="xl:col-span-2 rounded-xl border border-n-weak bg-n-solid-1 p-5"
        >
          <div
            class="flex flex-col gap-2 md:flex-row md:items-center md:justify-between"
          >
            <div>
              <h2 class="text-heading-2 text-n-slate-12">
                {{ t('VOICE_AI.TRANSCRIPT.TITLE') }}
              </h2>
              <p class="mb-0 mt-1 text-sm text-n-slate-11">
                {{ t('VOICE_AI.TRANSCRIPT.DESCRIPTION') }}
              </p>
            </div>
            <div class="flex items-center gap-2 text-xs text-n-slate-11">
              <span class="rounded-full bg-n-alpha-2 px-2 py-1">
                {{
                  t('VOICE_AI.TRANSCRIPT.TRANSCRIPT_COUNT', {
                    count: transcriptSegments.length,
                  })
                }}
              </span>
              <span class="rounded-full bg-n-alpha-2 px-2 py-1">
                {{
                  t('VOICE_AI.TRANSCRIPT.TOOL_COUNT', {
                    count: toolEvents.length,
                  })
                }}
              </span>
            </div>
          </div>

          <div
            v-if="!timelineEvents.length"
            class="mt-4 rounded-lg bg-n-alpha-2 p-4 text-sm text-n-slate-11"
          >
            {{ t('VOICE_AI.TRANSCRIPT.EMPTY') }}
          </div>
          <div v-else class="mt-4 flex flex-col gap-3">
            <div
              v-for="item in timelineEvents"
              :key="item.timelineId"
              class="rounded-lg border border-n-weak bg-n-alpha-2 p-3"
            >
              <div
                v-if="item.timelineType === 'tool'"
                class="flex flex-col gap-3"
              >
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0">
                    <div class="flex items-center gap-2">
                      <span class="i-lucide-wrench size-4 text-n-slate-11" />
                      <span
                        class="truncate text-sm font-medium text-n-slate-12"
                      >
                        {{ item.tool }}
                      </span>
                    </div>
                    <p class="mb-0 mt-1 text-xs text-n-slate-10">
                      {{ t('VOICE_AI.TRANSCRIPT.TOOL_EVENT') }}
                    </p>
                  </div>
                  <span
                    class="shrink-0 rounded-full px-2 py-1 text-xs font-medium capitalize"
                    :class="toolStatusClass(item.status)"
                  >
                    {{ item.status }}
                  </span>
                </div>

                <div
                  v-if="item.error_message"
                  class="rounded-md bg-n-ruby-3 px-3 py-2 text-sm text-n-ruby-11"
                >
                  {{ item.error_message }}
                </div>

                <div class="grid grid-cols-1 gap-2 md:grid-cols-2">
                  <details class="rounded-md bg-n-alpha-2 px-3 py-2">
                    <summary
                      class="cursor-pointer text-xs font-medium text-n-slate-11"
                    >
                      {{ t('VOICE_AI.TRANSCRIPT.ARGUMENTS') }}
                    </summary>
                    <pre
                      class="mb-0 mt-2 max-h-56 overflow-auto whitespace-pre-wrap break-words text-xs text-n-slate-12"
                    ><code>{{ formatJson(item.arguments) }}</code></pre>
                  </details>
                  <details class="rounded-md bg-n-alpha-2 px-3 py-2">
                    <summary
                      class="cursor-pointer text-xs font-medium text-n-slate-11"
                    >
                      {{ t('VOICE_AI.TRANSCRIPT.RESULT') }}
                    </summary>
                    <pre
                      class="mb-0 mt-2 max-h-56 overflow-auto whitespace-pre-wrap break-words text-xs text-n-slate-12"
                    ><code>{{ formatJson(item.result) }}</code></pre>
                  </details>
                </div>
              </div>
              <template v-else>
                <div class="mb-1 flex items-center justify-between gap-3">
                  <span class="text-sm font-medium text-n-slate-12 capitalize">
                    {{ item.role }}
                  </span>
                  <span class="text-xs text-n-slate-10">
                    {{ item.source }}
                  </span>
                </div>
                <p class="mb-0 whitespace-pre-wrap text-sm text-n-slate-12">
                  {{ item.text }}
                </p>
              </template>
            </div>
          </div>
        </section>
      </div>
    </template>
  </SettingsLayout>
</template>
