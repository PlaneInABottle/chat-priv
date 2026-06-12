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
const TOOL_PAYLOAD_CLASS =
  'm-0 max-h-48 overflow-auto rounded bg-n-solid-1 p-2 whitespace-pre-wrap';

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
  inbox_settings: [],
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
const voiceUsage = ref(null);
const selectedVoiceAgentId = ref('');
const selectedTestInboxId = ref('');
const callerName = ref('Test caller');
const callerNumber = ref('+900000000000');
const activeTab = ref('agents');
const currentCall = ref(null);
const isLoading = ref(false);
const isSavingAgent = ref(false);
const isCreatingCall = ref(false);
const isEnding = ref(false);
const isRefreshing = ref(false);

const agentForm = ref(clone(DEFAULT_AGENT));
const assignmentForm = ref({});
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
  { label: t('VOICE_AI.TABS.AGENTS'), value: 'agents' },
  { label: t('VOICE_AI.TABS.TEST'), value: 'test' },
  { label: t('VOICE_AI.TABS.USAGE'), value: 'usage' },
]);
const activeTabIndex = computed(() =>
  tabs.value.findIndex(tab => tab.value === activeTab.value)
);

const apiInboxes = computed(() =>
  (inboxes.value || []).filter(inbox => inbox.channel_type === INBOX_TYPES.API)
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

const selectedAgentSavedApiSettings = computed(() =>
  settings.value.filter(
    setting =>
      Number(setting.voice_agent_id) === Number(selectedVoiceAgentId.value) &&
      apiInboxes.value.some(
        inbox => Number(inbox.id) === Number(setting.inbox_id)
      )
  )
);

const selectedTestInboxSetting = computed(() =>
  selectedAgentSavedApiSettings.value.find(
    setting => Number(setting.inbox_id) === Number(selectedTestInboxId.value)
  )
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

const voiceAccessEnabled = computed(() => voiceUsage.value?.enabled === true);
const isVoiceAccessDisabled = computed(
  () => Boolean(voiceUsage.value) && !voiceAccessEnabled.value
);
const canSaveAgent = computed(
  () => voiceAccessEnabled.value && Boolean(agentForm.value.name?.trim())
);
const currentCallStatus = computed(() => currentCall.value?.status || '');
const isCurrentCallTerminal = computed(() =>
  TERMINAL_CALL_STATUSES.includes(currentCallStatus.value)
);
const hasCall = computed(() => Boolean(currentCall.value?.id));
const hasActiveTestCall = computed(
  () => hasCall.value && !isCurrentCallTerminal.value
);
const canEditTest = computed(
  () => voiceAccessEnabled.value && !hasActiveTestCall.value
);
const canStartTest = computed(
  () =>
    voiceAccessEnabled.value &&
    Boolean(selectedVoiceAgent.value?.enabled) &&
    Boolean(selectedTestInboxSetting.value) &&
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
const testToolEvents = computed(() => currentCall.value?.tool_events || []);
const timelineEvents = computed(() => {
  const transcriptItems = transcriptSegments.value.map(segment => ({
    ...segment,
    timelineType: 'transcript',
    timelineId: `transcript-${segment.id}`,
    sortAt: segment.created_at,
  }));
  const toolItems = testToolEvents.value.map(event => ({
    ...event,
    timelineType: 'tool_event',
    timelineId: `tool-${event.id}`,
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

const voiceUsageStatusClasses = computed(() => {
  if (voiceUsage.value?.status === 'disabled') {
    return 'border-n-slate-5 bg-n-slate-2';
  }
  if (voiceUsage.value?.status === 'exhausted') {
    return 'border-n-ruby-5 bg-n-ruby-2';
  }
  if (voiceUsage.value?.status === 'warning') {
    return 'border-n-amber-5 bg-n-amber-2';
  }
  return 'border-n-weak bg-n-alpha-1';
});

const assignmentStatuses = computed(() => [
  { label: t('VOICE_AI.ASSIGNMENTS.STATUS_TEST_ONLY'), value: 'test_only' },
  { label: t('VOICE_AI.ASSIGNMENTS.STATUS_READY'), value: 'ready' },
]);

const assignmentRows = computed(() =>
  apiInboxes.value
    .map(inbox => ({
      inbox,
      form: assignmentForm.value[String(inbox.id)],
    }))
    .filter(row => row.form)
);

const formatDateTime = value => {
  if (!value) return '-';

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));
};
const voiceUsageText = computed(() => {
  if (!voiceUsage.value) return t('VOICE_AI.USAGE.LOADING');
  if (voiceUsage.value.unlimited) {
    return t('VOICE_AI.USAGE.UNLIMITED_USED', {
      used: voiceUsage.value.used_minutes || 0,
    });
  }

  return t('VOICE_AI.USAGE.USED_OF_LIMIT', {
    used: voiceUsage.value.used_minutes || 0,
    limit: voiceUsage.value.limit_minutes || 0,
  });
});
const voiceRemainingText = computed(() => {
  if (!voiceUsage.value) return t('VOICE_AI.USAGE.LOADING');
  if (!voiceUsage.value.enabled) {
    return t('VOICE_AI.USAGE.DISABLED_REMAINING');
  }
  if (voiceUsage.value.unlimited) {
    return t('VOICE_AI.USAGE.UNLIMITED_REMAINING');
  }

  return t('VOICE_AI.USAGE.REMAINING', {
    count: voiceUsage.value.remaining_minutes || 0,
  });
});

const isToolEnabled = toolKey =>
  agentForm.value.tools_config.enabled.includes(toolKey);
const assignedAgentName = setting => {
  const agent = voiceAgents.value.find(
    item => Number(item.id) === Number(setting?.voice_agent_id)
  );
  return agent?.name || t('VOICE_AI.ASSIGNMENTS.UNKNOWN_AGENT');
};

const currentAssignmentForInbox = inboxId =>
  settings.value.find(setting => Number(setting.inbox_id) === Number(inboxId));

const isAssignedToAnotherAgent = row =>
  row.form.assigned &&
  row.form.assigned_voice_agent_id &&
  Number(row.form.assigned_voice_agent_id) !==
    Number(editingVoiceAgentId.value);

const assignedCount = agent =>
  settings.value.filter(
    setting => Number(setting.voice_agent_id) === Number(agent?.id)
  ).length;

const syncAssignmentForm = agent => {
  const rows = {};
  apiInboxes.value.forEach(inbox => {
    const existing = settings.value.find(
      setting => Number(setting.inbox_id) === Number(inbox.id)
    );
    rows[String(inbox.id)] = {
      assigned: Boolean(
        agent?.id && Number(existing?.voice_agent_id) === Number(agent.id)
      ),
      assignment_id: existing?.id || null,
      assigned_voice_agent_id: existing?.voice_agent_id || null,
      fallback_team_id: existing?.fallback_team_id || '',
      recording_enabled: Boolean(existing?.recording_enabled),
      status: existing?.status || 'test_only',
    };
  });
  assignmentForm.value = rows;
};

const syncAgentForm = agent => {
  if (!agent) {
    editingVoiceAgentId.value = null;
    agentForm.value = clone(DEFAULT_AGENT);
    syncAssignmentForm(null);
    return;
  }

  editingVoiceAgentId.value = agent?.id || null;
  agentForm.value = {
    ...clone(DEFAULT_AGENT),
    ...agent,
    tools_config: normalizeToolsConfig(agent?.tools_config),
    inbox_settings: agent?.inbox_settings || [],
  };
  syncAssignmentForm(agent);
};

const ensureSelectedTestInbox = () => {
  if (
    selectedTestInboxId.value &&
    selectedAgentSavedApiSettings.value.some(
      setting => Number(setting.inbox_id) === Number(selectedTestInboxId.value)
    )
  ) {
    return;
  }
  selectedTestInboxId.value =
    selectedAgentSavedApiSettings.value[0]?.inbox_id || '';
};

const refreshSettings = async () => {
  const response = await VoiceAPI.getSettings();
  settings.value = response.data?.payload || [];
};

const loadData = async () => {
  isLoading.value = true;
  try {
    await Promise.all([
      store.dispatch('inboxes/get'),
      store.dispatch('teams/get'),
    ]);
    const [agentResponse, settingsResponse, usageResponse] = await Promise.all([
      VoiceAPI.getAgents(),
      VoiceAPI.getSettings(),
      VoiceAPI.getUsage(),
    ]);
    voiceAgents.value = agentResponse.data?.payload || [];
    settings.value = settingsResponse.data?.payload || [];
    voiceUsage.value = usageResponse.data || null;
    selectedVoiceAgentId.value =
      selectedVoiceAgentId.value || voiceAgents.value[0]?.id || '';
    syncAgentForm(selectedVoiceAgent.value || voiceAgents.value[0]);
    ensureSelectedTestInbox();
  } catch {
    useAlert(t('VOICE_AI.SETUP.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const assignmentPayload = () =>
  assignmentRows.value
    .filter(row => row.form?.assigned)
    .map(row => ({
      inbox_id: row.inbox.id,
      fallback_team_id: row.form.fallback_team_id || null,
      recording_enabled: Boolean(row.form.recording_enabled),
      status: row.form.status || 'test_only',
    }));

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
      inbox_settings: assignmentPayload(),
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
    await refreshSettings();
    syncAgentForm(saved);
    ensureSelectedTestInbox();
    useAlert(t('VOICE_AI.AGENTS.SAVE_SUCCESS'));
  } catch {
    useAlert(t('VOICE_AI.AGENTS.SAVE_ERROR'));
  } finally {
    isSavingAgent.value = false;
  }
};

const createNewVoiceAgent = () => {
  if (!voiceAccessEnabled.value) return;

  selectedVoiceAgentId.value = '';
  syncAgentForm(null);
  activeTab.value = 'agents';
};

const editVoiceAgent = agent => {
  selectedVoiceAgentId.value = agent.id;
  syncAgentForm(agent);
  ensureSelectedTestInbox();
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
    const response = await VoiceAPI.createTestCall({
      inbox_id: selectedTestInboxId.value,
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

const refreshUsage = async () => {
  const response = await VoiceAPI.getUsage();
  voiceUsage.value = response.data;
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
    await refreshUsage();
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

const onStatusChanged = data => {
  if (!currentCall.value || data.call_id !== currentCall.value.id) return;
  const { transcript_segments, tool_events, ...scalarFields } = data;
  currentCall.value = { ...currentCall.value, ...scalarFields };
};

const onToolEvent = data => {
  if (!currentCall.value || data.call_id !== currentCall.value.id) return;
  const events = currentCall.value.tool_events || [];
  if (events.some(event => event.id === data.event.id)) return;
  currentCall.value = {
    ...currentCall.value,
    tool_events: [...events, data.event],
  };
};

const formatToolPayload = value => {
  if (!value || Object.keys(value).length === 0) return '{}';
  return JSON.stringify(value, null, 2);
};

watch(selectedVoiceAgentId, () => {
  if (selectedVoiceAgent.value) {
    syncAgentForm(selectedVoiceAgent.value);
    ensureSelectedTestInbox();
  }
});

let voiceEventsSubscribed = false;
const subscribeToVoiceEvents = () => {
  if (voiceEventsSubscribed) return;
  voiceEventsSubscribed = true;
  emitter.on('voice.transcript_segment', onTranscriptSegment);
  emitter.on('voice.status_changed', onStatusChanged);
  emitter.on('voice.tool_event', onToolEvent);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, refreshCall);
};
const unsubscribeFromVoiceEvents = () => {
  if (!voiceEventsSubscribed) return;
  voiceEventsSubscribed = false;
  emitter.off('voice.transcript_segment', onTranscriptSegment);
  emitter.off('voice.status_changed', onStatusChanged);
  emitter.off('voice.tool_event', onToolEvent);
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
          v-if="activeTab === 'agents'"
          class="grid grid-cols-1 gap-6 xl:grid-cols-[320px_minmax(0,1fr)]"
        >
          <aside class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <div class="mb-4 flex items-center justify-between gap-3">
              <div>
                <h2 class="m-0 text-heading-2 text-n-slate-12">
                  {{ t('VOICE_AI.AGENTS.TITLE') }}
                </h2>
                <p class="m-0 mt-1 text-xs text-n-slate-11">
                  {{ t('VOICE_AI.AGENTS.LIST_HELP') }}
                </p>
              </div>
              <Button
                icon="i-lucide-plus"
                size="sm"
                variant="outline"
                color="slate"
                :label="t('VOICE_AI.AGENTS.NEW')"
                :disabled="!voiceAccessEnabled"
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
                class="rounded-lg border p-3 text-left transition"
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
                <span class="mt-1 block text-xs text-n-slate-11">
                  {{
                    t('VOICE_AI.AGENTS.ASSIGNED_COUNT', {
                      count: assignedCount(agent),
                    })
                  }}
                </span>
                <span
                  v-if="!voiceAccessEnabled"
                  class="mt-2 block text-xs text-n-slate-10"
                >
                  {{ t('VOICE_AI.AGENTS.DISABLED_BY_ADMIN') }}
                </span>
              </button>
            </div>
          </aside>

          <div
            class="rounded-xl border border-n-weak bg-n-solid-1 p-5 flex flex-col gap-5"
          >
            <div>
              <h2 class="m-0 text-heading-2 text-n-slate-12">
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
                :disabled="!voiceAccessEnabled"
              />
              <Input
                v-model="agentForm.greeting"
                :label="t('VOICE_AI.AGENTS.GREETING')"
                :disabled="!voiceAccessEnabled"
              />
            </div>

            <div
              class="flex items-center justify-between gap-4 rounded-lg bg-n-alpha-2 p-3"
            >
              <div>
                <p class="mb-1 text-sm font-medium text-n-slate-12">
                  {{ t('VOICE_AI.AGENTS.ENABLED') }}
                </p>
                <p class="mb-0 text-sm text-n-slate-11">
                  {{ t('VOICE_AI.AGENTS.ENABLED_HELP') }}
                </p>
              </div>
              <Switch
                v-model="agentForm.enabled"
                :disabled="!voiceAccessEnabled"
              />
            </div>

            <label class="flex flex-col gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('VOICE_AI.AGENTS.PROMPT') }}
              </span>
              <textarea
                v-model="agentForm.prompt"
                rows="10"
                :disabled="!voiceAccessEnabled"
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
                    :disabled="!voiceAccessEnabled"
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

            <div class="rounded-lg border border-n-weak bg-n-alpha-1 p-4">
              <div
                class="mb-4 flex flex-col gap-2 md:flex-row md:items-start md:justify-between"
              >
                <div>
                  <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                    {{ t('VOICE_AI.ASSIGNMENTS.TITLE') }}
                  </h3>
                  <p class="m-0 mt-1 text-sm text-n-slate-11">
                    {{ t('VOICE_AI.ASSIGNMENTS.DESCRIPTION') }}
                  </p>
                </div>
                <span
                  class="rounded-full bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
                >
                  {{
                    t('VOICE_AI.AGENTS.ASSIGNED_COUNT', {
                      count: assignmentPayload().length,
                    })
                  }}
                </span>
              </div>

              <div v-if="!apiInboxes.length" class="text-sm text-n-ruby-9">
                {{ t('VOICE_AI.SETUP.NO_API_INBOX') }}
              </div>

              <div v-else class="flex flex-col divide-y divide-n-weak">
                <div
                  v-for="row in assignmentRows"
                  :key="row.inbox.id"
                  class="grid grid-cols-1 gap-3 py-4 xl:grid-cols-[minmax(0,1fr)_180px_120px_120px]"
                >
                  <label class="flex min-w-0 items-start gap-3">
                    <input
                      v-model="row.form.assigned"
                      type="checkbox"
                      class="mt-1 h-4 w-4 rounded border-n-slate-6 text-n-brand"
                      :disabled="!voiceAccessEnabled"
                    />
                    <span class="min-w-0">
                      <span
                        class="block truncate text-sm font-medium text-n-slate-12"
                      >
                        {{ row.inbox.name }}
                      </span>
                      <span class="mt-1 block text-xs text-n-slate-11">
                        {{ t('VOICE_AI.ASSIGNMENTS.API_SANDBOX') }}
                      </span>
                      <span
                        v-if="isAssignedToAnotherAgent(row)"
                        class="mt-1 block text-xs text-n-amber-11"
                      >
                        {{
                          t('VOICE_AI.ASSIGNMENTS.ASSIGNED_TO', {
                            agent: assignedAgentName(
                              currentAssignmentForInbox(row.inbox.id)
                            ),
                          })
                        }}
                      </span>
                    </span>
                  </label>

                  <label class="flex flex-col gap-1">
                    <span class="text-xs text-n-slate-11">
                      {{ t('VOICE_AI.SETUP.FALLBACK_TEAM') }}
                    </span>
                    <select
                      v-model="row.form.fallback_team_id"
                      :disabled="!voiceAccessEnabled || !row.form.assigned"
                      class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      <option value="">{{ t('VOICE_AI.SETUP.NONE') }}</option>
                      <option
                        v-for="team in teams"
                        :key="team.id"
                        :value="team.id"
                      >
                        {{ team.name }}
                      </option>
                    </select>
                  </label>

                  <label class="flex flex-col gap-1">
                    <span class="text-xs text-n-slate-11">
                      {{ t('VOICE_AI.ASSIGNMENTS.STATUS') }}
                    </span>
                    <select
                      v-model="row.form.status"
                      :disabled="!voiceAccessEnabled || !row.form.assigned"
                      class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      <option
                        v-for="status in assignmentStatuses"
                        :key="status.value"
                        :value="status.value"
                      >
                        {{ status.label }}
                      </option>
                    </select>
                  </label>

                  <div class="flex items-center justify-between gap-3">
                    <span class="text-xs text-n-slate-11">
                      {{ t('VOICE_AI.SETUP.RECORDING') }}
                    </span>
                    <Switch
                      v-model="row.form.recording_enabled"
                      :disabled="!voiceAccessEnabled || !row.form.assigned"
                    />
                  </div>
                </div>
              </div>
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
              <h2 class="m-0 text-heading-2 text-n-slate-12">
                {{ t('VOICE_AI.TEST.TITLE') }}
              </h2>
              <p class="mb-0 mt-1 text-sm text-n-slate-11">
                {{ t('VOICE_AI.TEST.DESCRIPTION') }}
              </p>
            </div>

            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
              <label class="flex flex-col gap-1">
                <span class="text-heading-3 text-n-slate-12">
                  {{ t('VOICE_AI.SETUP.VOICE_AGENT') }}
                </span>
                <select
                  v-model="selectedVoiceAgentId"
                  :disabled="!canEditTest"
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
                  {{ t('VOICE_AI.SETUP.INBOX') }}
                </span>
                <select
                  v-model="selectedTestInboxId"
                  :disabled="
                    !canEditTest || !selectedAgentSavedApiSettings.length
                  "
                  class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <option value="">{{ t('VOICE_AI.SETUP.NONE') }}</option>
                  <option
                    v-for="setting in selectedAgentSavedApiSettings"
                    :key="setting.id"
                    :value="setting.inbox_id"
                  >
                    {{ setting.inbox_name }}
                  </option>
                </select>
              </label>
            </div>

            <div
              v-if="selectedVoiceAgent && !selectedAgentSavedApiSettings.length"
              class="rounded-lg border border-n-amber-5 bg-n-amber-2 p-3 text-sm text-n-amber-11"
            >
              {{ t('VOICE_AI.TEST.NO_ASSIGNED_INBOX') }}
            </div>

            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
              <Input
                v-model="callerName"
                :label="t('VOICE_AI.SETUP.CALLER_NAME')"
                :disabled="!canEditTest"
              />
              <Input
                v-model="callerNumber"
                :label="t('VOICE_AI.SETUP.CALLER_NUMBER')"
                :disabled="!canEditTest"
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
              <h2 class="m-0 text-heading-2 text-n-slate-12">
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
                <h2 class="m-0 text-heading-2 text-n-slate-12">
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
                      count: testToolEvents.length,
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
                class="rounded-lg border border-n-weak p-3"
                :class="
                  item.timelineType === 'tool_event'
                    ? 'bg-n-amber-2'
                    : 'bg-n-alpha-2'
                "
              >
                <template v-if="item.timelineType === 'tool_event'">
                  <div class="mb-2 flex items-center justify-between gap-3">
                    <div class="flex min-w-0 items-center gap-2">
                      <span class="text-sm font-medium text-n-slate-12">
                        {{ t('VOICE_AI.TRANSCRIPT.TOOL_EVENT') }}
                      </span>
                      <span class="truncate text-sm text-n-slate-11">
                        {{ item.tool }}
                      </span>
                    </div>
                    <span class="text-xs text-n-slate-10">
                      {{ item.status }}
                    </span>
                  </div>
                  <p
                    v-if="item.error_message"
                    class="mb-2 text-sm text-n-ruby-11"
                  >
                    {{ item.error_message }}
                  </p>
                  <details class="text-xs text-n-slate-11">
                    <summary class="cursor-pointer font-medium text-n-slate-12">
                      {{ t('VOICE_AI.TRANSCRIPT.TOOL_DETAILS') }}
                    </summary>
                    <div class="mt-2 grid grid-cols-1 gap-2 lg:grid-cols-2">
                      <div>
                        <p class="m-0 mb-1 font-medium">
                          {{ t('VOICE_AI.TRANSCRIPT.ARGUMENTS') }}
                        </p>
                        <pre :class="TOOL_PAYLOAD_CLASS">{{
                          formatToolPayload(item.arguments)
                        }}</pre>
                      </div>
                      <div>
                        <p class="m-0 mb-1 font-medium">
                          {{ t('VOICE_AI.TRANSCRIPT.RESULT') }}
                        </p>
                        <pre :class="TOOL_PAYLOAD_CLASS">{{
                          formatToolPayload(item.result)
                        }}</pre>
                      </div>
                    </div>
                  </details>
                </template>
                <template v-else>
                  <div class="mb-1 flex items-center justify-between gap-3">
                    <span
                      class="text-sm font-medium text-n-slate-12 capitalize"
                    >
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
        </section>

        <section
          v-if="activeTab === 'usage'"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-5"
        >
          <section
            class="rounded-lg border p-4"
            :class="voiceUsageStatusClasses"
          >
            <div
              class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between"
            >
              <div>
                <h2 class="m-0 text-heading-2 text-n-slate-12">
                  {{ t('VOICE_AI.USAGE.TITLE') }}
                </h2>
                <p class="m-0 mt-1 text-sm text-n-slate-11">
                  {{
                    isVoiceAccessDisabled
                      ? t('VOICE_AI.USAGE.DISABLED_HELP')
                      : t('VOICE_AI.USAGE.HELP')
                  }}
                </p>
              </div>
              <div class="md:text-right">
                <p class="m-0 text-2xl font-semibold text-n-slate-12">
                  {{ voiceRemainingText }}
                </p>
                <p class="m-0 mt-1 text-xs text-n-slate-11">
                  {{ voiceUsageText }}
                </p>
              </div>
            </div>

            <div
              class="mt-4 grid grid-cols-1 gap-px overflow-hidden rounded-lg border border-n-weak bg-n-slate-4 md:grid-cols-4"
            >
              <div class="bg-n-alpha-1 p-3">
                <span class="text-xs text-n-slate-11">
                  {{ t('VOICE_AI.USAGE.RESET_AT') }}
                </span>
                <p class="m-0 mt-1 text-sm font-medium text-n-slate-12">
                  {{ formatDateTime(voiceUsage?.reset_at) }}
                </p>
              </div>
              <div class="bg-n-alpha-1 p-3">
                <span class="text-xs text-n-slate-11">
                  {{ t('VOICE_AI.USAGE.MAX_DURATION') }}
                </span>
                <p class="m-0 mt-1 text-sm font-medium text-n-slate-12">
                  {{
                    t('VOICE_AI.USAGE.MINUTES', {
                      count: voiceUsage?.max_call_duration_minutes || 15,
                    })
                  }}
                </p>
              </div>
              <div class="bg-n-alpha-1 p-3">
                <span class="text-xs text-n-slate-11">
                  {{ t('VOICE_AI.USAGE.CONCURRENT_LIMIT') }}
                </span>
                <p class="m-0 mt-1 text-sm font-medium text-n-slate-12">
                  {{
                    voiceUsage?.concurrent_call_limit === 0
                      ? t('VOICE_AI.USAGE.UNLIMITED_SHORT')
                      : voiceUsage?.concurrent_call_limit || 1
                  }}
                </p>
              </div>
              <div class="bg-n-alpha-1 p-3">
                <span class="text-xs text-n-slate-11">
                  {{ t('VOICE_AI.USAGE.ACTIVE_CALLS') }}
                </span>
                <p class="m-0 mt-1 text-sm font-medium text-n-slate-12">
                  {{ voiceUsage?.active_calls || 0 }}
                </p>
              </div>
            </div>
          </section>
        </section>
      </div>
    </template>
  </SettingsLayout>
</template>
