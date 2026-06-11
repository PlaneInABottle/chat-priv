<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import VoiceAPI from 'dashboard/api/voice';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useLivekitVoiceSession } from 'dashboard/composables/useLivekitVoiceSession';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const TERMINAL_CALL_STATUSES = [
  'completed',
  'no-answer',
  'no_answer',
  'failed',
];
const DEFAULT_AGENT = {
  name: 'Voice Assistant',
  enabled: true,
  greeting: 'Merhaba, size nasil yardimci olabilirim?',
  prompt:
    'Yalnizca dogal Istanbul Turkcesiyle konus. Kisa, net ve sakin musteri destek cevaplari ver.',
  tools_config: {
    enabled: ['human_handoff', 'end_customer_call'],
    human_handoff: { allowed_labels: [] },
    ikas_lookup_order: { enabled: false },
    ikas_catalog_search: {},
    end_customer_call: {},
  },
  config: {},
};

const clone = value => JSON.parse(JSON.stringify(value));

const normalizeToolsConfig = toolsConfig => {
  const tools = toolsConfig || {};
  return {
    enabled: Array.from(new Set(tools.enabled || [])).filter(Boolean),
    human_handoff: {
      allowed_labels: Array.from(
        new Set(tools.human_handoff?.allowed_labels || [])
      ).filter(Boolean),
    },
    ikas_lookup_order: {
      enabled: Boolean(tools.ikas_lookup_order?.enabled),
    },
    ikas_catalog_search: {},
    end_customer_call: {},
  };
};

const store = useStore();
const { t } = useI18n();

const settings = ref([]);
const voiceAgents = ref([]);
const selectedInboxId = ref('');
const selectedVoiceAgentId = ref('');
const selectedFallbackTeamId = ref('');
const recordingEnabled = ref(false);
const callerName = ref('Test caller');
const callerNumber = ref('+900000000000');
const activeTab = ref('setup');
const currentCall = ref(null);
const isLoading = ref(false);
const isSaving = ref(false);
const isSavingAgent = ref(false);
const isCreatingCall = ref(false);
const isEnding = ref(false);
const isRefreshing = ref(false);

const agentForm = ref(clone(DEFAULT_AGENT));
const editingVoiceAgentId = ref(null);

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
const teams = useMapGetter('teams/getTeams');

const tabs = computed(() => [
  { label: t('VOICE_AI.TABS.SETUP'), value: 'setup' },
  { label: t('VOICE_AI.TABS.AGENTS'), value: 'agents' },
  { label: t('VOICE_AI.TABS.TEST'), value: 'test' },
]);
const activeTabIndex = computed(() =>
  tabs.value.findIndex(tab => tab.value === activeTab.value)
);

const apiInboxes = computed(() =>
  (inboxes.value || []).filter(inbox => inbox.channel_type === INBOX_TYPES.API)
);
const selectedSetting = computed(() =>
  settings.value.find(
    setting => Number(setting.inbox_id) === Number(selectedInboxId.value)
  )
);
const selectedVoiceAgent = computed(() =>
  voiceAgents.value.find(
    agent => Number(agent.id) === Number(selectedVoiceAgentId.value)
  )
);
const availableTools = computed(
  () =>
    selectedVoiceAgent.value?.available_tools ||
    voiceAgents.value[0]?.available_tools ||
    []
);
const isIkasAvailable = computed(() => {
  const integration = selectedVoiceAgent.value?.ikas_integration;
  return integration?.feature_enabled && integration?.state === 'connected';
});
const isIkasCatalogReady = computed(
  () =>
    selectedVoiceAgent.value?.ikas_integration?.catalog_sync?.status ===
    'completed'
);

const canSave = computed(() => Boolean(selectedInboxId.value));
const canSaveAgent = computed(() => Boolean(agentForm.value.name?.trim()));
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
    Boolean(selectedVoiceAgentId.value) &&
    Boolean(selectedVoiceAgent.value?.enabled) &&
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
  return [...transcriptItems, ...toolItems].sort(
    (a, b) =>
      new Date(a.sortAt || 0).getTime() - new Date(b.sortAt || 0).getTime()
  );
});

const sessionStatusLabel = computed(
  () =>
    ({
      disconnected: t('VOICE_AI.SESSION.DISCONNECTED'),
      connecting: t('VOICE_AI.SESSION.CONNECTING'),
      connected: t('VOICE_AI.SESSION.CONNECTED'),
      failed: t('VOICE_AI.SESSION.FAILED'),
    })[sessionStatus.value] || sessionStatus.value
);
const callStatusLabel = computed(
  () => currentCallStatus.value || t('VOICE_AI.SESSION.NOT_STARTED')
);

const formatJson = value => JSON.stringify(value || {}, null, 2);
const isToolEnabled = toolKey =>
  agentForm.value.tools_config.enabled.includes(toolKey);
const toolStatusClass = status => {
  if (status === 'executed') return 'text-n-teal-11 bg-n-teal-3';
  if (status === 'error' || status === 'rejected') {
    return 'text-n-ruby-11 bg-n-ruby-3';
  }
  return 'text-n-slate-11 bg-n-alpha-2';
};
const isHandoffToolEvent = item =>
  item?.tool === 'request_human_handoff' ||
  item?.result?.terminal_action === 'handoff';
const handoffToolSummary = item =>
  item?.result?.customer_message ||
  item?.result?.reason ||
  item?.arguments?.reason ||
  t('VOICE_AI.TRANSCRIPT.HANDOFF_PREVIEW');

const syncFormFromSetting = setting => {
  selectedVoiceAgentId.value =
    setting?.voice_agent_id || voiceAgents.value[0]?.id || '';
  selectedFallbackTeamId.value = setting?.fallback_team_id || '';
  recordingEnabled.value = Boolean(setting?.recording_enabled);
};

const syncAgentForm = agent => {
  if (!agent) {
    editingVoiceAgentId.value = null;
    agentForm.value = clone(DEFAULT_AGENT);
    return;
  }

  editingVoiceAgentId.value = agent?.id || null;
  agentForm.value = {
    ...clone(DEFAULT_AGENT),
    ...agent,
    tools_config: normalizeToolsConfig(agent?.tools_config),
  };
};

const loadData = async () => {
  isLoading.value = true;
  try {
    await Promise.all([
      store.dispatch('inboxes/get'),
      store.dispatch('teams/get'),
    ]);
    const [agentResponse, settingsResponse] = await Promise.all([
      VoiceAPI.getAgents(),
      VoiceAPI.getSettings(),
    ]);
    voiceAgents.value = agentResponse.data?.payload || [];
    settings.value = settingsResponse.data?.payload || [];
    if (!selectedInboxId.value && apiInboxes.value.length) {
      selectedInboxId.value = apiInboxes.value[0].id;
    }
    syncFormFromSetting(selectedSetting.value);
    syncAgentForm(selectedVoiceAgent.value || voiceAgents.value[0]);
  } catch {
    useAlert(t('VOICE_AI.SETUP.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const settingPayload = () => ({
  inbox_id: selectedInboxId.value,
  voice_agent_id: selectedVoiceAgentId.value || null,
  fallback_team_id: selectedFallbackTeamId.value || null,
  recording_enabled: recordingEnabled.value,
  status: 'test_only',
});

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
  } catch {
    if (!silent) useAlert(t('VOICE_AI.SETUP.SAVE_ERROR'));
    throw new Error('voice setting save failed');
  } finally {
    isSaving.value = false;
  }
};

const saveVoiceAgent = async () => {
  if (!canSaveAgent.value) return;
  isSavingAgent.value = true;
  try {
    const payload = {
      name: agentForm.value.name,
      enabled: agentForm.value.enabled,
      greeting: agentForm.value.greeting,
      prompt: agentForm.value.prompt,
      tools_config: agentForm.value.tools_config,
    };
    const response = editingVoiceAgentId.value
      ? await VoiceAPI.updateAgent(editingVoiceAgentId.value, payload)
      : await VoiceAPI.createAgent(payload);
    const saved = response.data;
    voiceAgents.value = [
      ...voiceAgents.value.filter(agent => agent.id !== saved.id),
      saved,
    ].sort((a, b) => a.id - b.id);
    selectedVoiceAgentId.value = saved.id;
    syncAgentForm(saved);
    useAlert(t('VOICE_AI.AGENTS.SAVE_SUCCESS'));
  } catch {
    useAlert(t('VOICE_AI.AGENTS.SAVE_ERROR'));
  } finally {
    isSavingAgent.value = false;
  }
};

const createNewVoiceAgent = () => {
  selectedVoiceAgentId.value = '';
  syncAgentForm(null);
  activeTab.value = 'agents';
};

const editVoiceAgent = agent => {
  selectedVoiceAgentId.value = agent.id;
  syncAgentForm(agent);
  activeTab.value = 'agents';
};

const toggleTool = toolKey => {
  const enabled = new Set(agentForm.value.tools_config.enabled);
  if (enabled.has(toolKey)) {
    enabled.delete(toolKey);
  } else {
    enabled.add(toolKey);
  }
  agentForm.value = {
    ...agentForm.value,
    tools_config: {
      ...agentForm.value.tools_config,
      enabled: Array.from(enabled),
      ikas_lookup_order: {
        ...agentForm.value.tools_config.ikas_lookup_order,
        enabled: enabled.has('ikas_lookup_order'),
      },
    },
  };
};

const createTestCall = async () => {
  if (!canStartTest.value) return;
  isCreatingCall.value = true;
  try {
    await saveSettings({ silent: true });
    const response = await VoiceAPI.createTestCall({
      inbox_id: selectedInboxId.value,
      voice_agent_id: selectedVoiceAgentId.value,
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

const onTranscriptSegment = data => {
  if (!currentCall.value || data.call_id !== currentCall.value.id) return;
  const segments = currentCall.value.transcript_segments || [];
  if (segments.some(segment => segment.id === data.segment.id)) return;
  currentCall.value = {
    ...currentCall.value,
    transcript_segments: [...segments, data.segment],
  };
};

const onToolEvent = data => {
  if (!currentCall.value || data.call_id !== currentCall.value.id) return;
  const events = currentCall.value.tool_events || [];
  if (events.some(event => event.id === data.tool_event.id)) return;
  currentCall.value = {
    ...currentCall.value,
    tool_events: [...events, data.tool_event],
  };
};

const onStatusChanged = data => {
  if (!currentCall.value || data.call_id !== currentCall.value.id) return;
  const { transcript_segments, tool_events, ...scalarFields } = data;
  currentCall.value = { ...currentCall.value, ...scalarFields };
};

watch(selectedInboxId, () => syncFormFromSetting(selectedSetting.value));
watch(selectedVoiceAgentId, () => {
  if (selectedVoiceAgent.value) syncAgentForm(selectedVoiceAgent.value);
});

let voiceEventsSubscribed = false;
const subscribeToVoiceEvents = () => {
  if (voiceEventsSubscribed) return;
  voiceEventsSubscribed = true;
  emitter.on('voice.transcript_segment', onTranscriptSegment);
  emitter.on('voice.tool_event', onToolEvent);
  emitter.on('voice.status_changed', onStatusChanged);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, refreshCall);
};
const unsubscribeFromVoiceEvents = () => {
  if (!voiceEventsSubscribed) return;
  voiceEventsSubscribed = false;
  emitter.off('voice.transcript_segment', onTranscriptSegment);
  emitter.off('voice.tool_event', onToolEvent);
  emitter.off('voice.status_changed', onStatusChanged);
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, refreshCall);
};

onMounted(() => {
  loadData();
  subscribeToVoiceEvents();
});
onBeforeUnmount(unsubscribeFromVoiceEvents);
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
      <div class="flex flex-col gap-6">
        <TabBar
          :tabs="tabs"
          :initial-active-tab="activeTabIndex"
          @tab-changed="tab => (activeTab = tab.value)"
        />

        <section
          v-if="activeTab === 'setup'"
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

          <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
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
                {{ t('VOICE_AI.SETUP.VOICE_AGENT') }}
              </span>
              <select
                v-model="selectedVoiceAgentId"
                :disabled="!canEditSetup"
                class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <option value="">{{ t('VOICE_AI.SETUP.NONE') }}</option>
                <option
                  v-for="agent in voiceAgents"
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
                <option value="">{{ t('VOICE_AI.SETUP.NONE') }}</option>
                <option v-for="team in teams" :key="team.id" :value="team.id">
                  {{ team.name }}
                </option>
              </select>
            </label>
          </div>

          <div
            class="flex items-center justify-between rounded-lg bg-n-alpha-2 p-3"
          >
            <div>
              <p class="mb-1 text-sm font-medium text-n-slate-12">
                {{ t('VOICE_AI.SETUP.RECORDING') }}
              </p>
              <p class="mb-0 text-sm text-n-slate-11">
                {{ t('VOICE_AI.SETUP.RECORDING_HELP') }}
              </p>
            </div>
            <Switch v-model="recordingEnabled" :disabled="!canEditSetup" />
          </div>

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
              :label="t('VOICE_AI.AGENTS.CREATE')"
              icon="i-lucide-bot"
              variant="outline"
              color="slate"
              @click="createNewVoiceAgent"
            />
          </div>
        </section>

        <section
          v-if="activeTab === 'agents'"
          class="grid grid-cols-1 gap-6 xl:grid-cols-[320px_minmax(0,1fr)]"
        >
          <aside class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <div class="mb-4 flex items-center justify-between gap-3">
              <h2 class="text-heading-2 text-n-slate-12">
                {{ t('VOICE_AI.AGENTS.TITLE') }}
              </h2>
              <Button
                icon="i-lucide-plus"
                size="sm"
                variant="outline"
                color="slate"
                :label="t('VOICE_AI.AGENTS.NEW')"
                @click="createNewVoiceAgent"
              />
            </div>
            <div v-if="!voiceAgents.length" class="text-sm text-n-slate-11">
              {{ t('VOICE_AI.AGENTS.EMPTY') }}
            </div>
            <div v-else class="flex flex-col gap-2">
              <button
                v-for="agent in voiceAgents"
                :key="agent.id"
                type="button"
                class="rounded-lg border p-3 text-left"
                :class="
                  editingVoiceAgentId === agent.id
                    ? 'border-n-brand bg-n-brand/5'
                    : 'border-n-weak bg-n-alpha-2 hover:bg-n-alpha-3'
                "
                @click="editVoiceAgent(agent)"
              >
                <span class="block text-sm font-medium text-n-slate-12">
                  {{ agent.name }}
                </span>
                <span class="mt-1 block text-xs text-n-slate-11">
                  {{
                    agent.enabled
                      ? t('VOICE_AI.AGENTS.STATUS_ENABLED')
                      : t('VOICE_AI.AGENTS.STATUS_DISABLED')
                  }}
                </span>
              </button>
            </div>
          </aside>

          <div
            class="rounded-xl border border-n-weak bg-n-solid-1 p-5 flex flex-col gap-5"
          >
            <div>
              <h2 class="text-heading-2 text-n-slate-12">
                {{ t('VOICE_AI.AGENTS.EDITOR_TITLE') }}
              </h2>
              <p class="mb-0 mt-1 text-sm text-n-slate-11">
                {{ t('VOICE_AI.AGENTS.EDITOR_DESCRIPTION') }}
              </p>
            </div>

            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
              <Input
                v-model="agentForm.name"
                :label="t('VOICE_AI.AGENTS.NAME')"
              />
              <Input
                v-model="agentForm.greeting"
                :label="t('VOICE_AI.AGENTS.GREETING')"
              />
            </div>

            <div
              class="flex items-center justify-between rounded-lg bg-n-alpha-2 p-3"
            >
              <div>
                <p class="mb-1 text-sm font-medium text-n-slate-12">
                  {{ t('VOICE_AI.AGENTS.ENABLED') }}
                </p>
                <p class="mb-0 text-sm text-n-slate-11">
                  {{ t('VOICE_AI.AGENTS.ENABLED_HELP') }}
                </p>
              </div>
              <Switch v-model="agentForm.enabled" />
            </div>

            <label class="flex flex-col gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('VOICE_AI.AGENTS.PROMPT') }}
              </span>
              <textarea
                v-model="agentForm.prompt"
                rows="8"
                class="rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 resize-y"
              />
            </label>

            <div>
              <h3 class="mb-2 text-sm font-medium text-n-slate-12">
                {{ t('VOICE_AI.AGENTS.TOOLS') }}
              </h3>
              <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
                <label
                  v-for="tool in availableTools"
                  :key="tool.key"
                  class="flex items-start gap-3 rounded-lg border border-n-weak bg-n-alpha-2 p-3"
                >
                  <input
                    type="checkbox"
                    class="mt-1 h-4 w-4 rounded border-n-slate-6 text-n-brand"
                    :checked="isToolEnabled(tool.key)"
                    @change="toggleTool(tool.key)"
                  />
                  <span class="min-w-0">
                    <span class="block text-sm font-medium text-n-slate-12">
                      {{ tool.name }}
                    </span>
                    <span class="mt-1 block text-xs text-n-slate-11">
                      {{ tool.description }}
                    </span>
                  </span>
                </label>
              </div>
              <p class="mb-0 mt-3 text-xs text-n-slate-11">
                {{
                  isIkasAvailable
                    ? isIkasCatalogReady
                      ? t('VOICE_AI.AGENTS.IKAS_READY')
                      : t('VOICE_AI.AGENTS.IKAS_CATALOG_NOT_SYNCED')
                    : t('VOICE_AI.AGENTS.IKAS_NOT_CONNECTED')
                }}
              </p>
            </div>

            <div class="flex justify-end">
              <Button
                :label="t('VOICE_AI.AGENTS.SAVE')"
                icon="i-lucide-save"
                :disabled="!canSaveAgent"
                :is-loading="isSavingAgent"
                @click="saveVoiceAgent"
              />
            </div>
          </div>
        </section>

        <section
          v-if="activeTab === 'test'"
          class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_360px]"
        >
          <div
            class="rounded-xl border border-n-weak bg-n-solid-1 p-5 flex flex-col gap-4"
          >
            <div>
              <h2 class="text-heading-2 text-n-slate-12">
                {{ t('VOICE_AI.TEST.TITLE') }}
              </h2>
              <p class="mb-0 mt-1 text-sm text-n-slate-11">
                {{ t('VOICE_AI.TEST.DESCRIPTION') }}
              </p>
            </div>
            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
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
            <Button
              :label="t('VOICE_AI.SETUP.START_TEST')"
              icon="i-lucide-phone-call"
              :disabled="!canStartTest"
              :is-loading="isCreatingCall"
              @click="createTestCall"
            />
          </div>

          <aside
            class="rounded-xl border border-n-weak bg-n-solid-1 p-5 flex flex-col gap-4"
          >
            <div>
              <h2 class="text-heading-2 text-n-slate-12">
                {{ t('VOICE_AI.SESSION.TITLE') }}
              </h2>
              <p class="mb-0 mt-1 truncate text-sm text-n-slate-11">
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
                    v-if="isHandoffToolEvent(item)"
                    class="rounded-lg border border-n-amber-6 bg-n-amber-3 px-3 py-3"
                  >
                    <p class="mb-1 text-sm font-medium text-n-amber-12">
                      {{ t('VOICE_AI.TRANSCRIPT.HANDOFF_TITLE') }}
                    </p>
                    <p class="mb-0 text-sm text-n-amber-11">
                      {{ handoffToolSummary(item) }}
                    </p>
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
                    <span
                      class="text-sm font-medium text-n-slate-12 capitalize"
                    >
                      {{ item.role }}
                    </span>
                    <span class="text-xs text-n-slate-10">{{
                      item.source
                    }}</span>
                  </div>
                  <p class="mb-0 whitespace-pre-wrap text-sm text-n-slate-12">
                    {{ item.text }}
                  </p>
                </template>
              </div>
            </div>
          </section>
        </section>
      </div>
    </template>
  </SettingsLayout>
</template>
