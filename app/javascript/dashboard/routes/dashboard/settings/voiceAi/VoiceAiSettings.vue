<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router';

import VoiceAPI from 'dashboard/api/voice';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useVoiceSession } from 'dashboard/composables/useVoiceSession';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import AssistantReleaseHistoryDialog from '../aiAgent/components/AssistantReleaseHistoryDialog.vue';
import ImprovementCreditsSummary from '../aiAgent/components/ImprovementCreditsSummary.vue';
import KnowledgeSourceSelector from '../aiAgent/components/KnowledgeSourceSelector.vue';
import ResponsiveTabNavigation from '../components/ResponsiveTabNavigation.vue';
import VoiceCallActivity from './VoiceCallActivity.vue';
import VoicePublishDialog from './VoicePublishDialog.vue';

const TERMINAL_CALL_STATUSES = [
  'completed',
  'no-answer',
  'no_answer',
  'failed',
];
const RECORDING_STATUSES = ['completed', 'active', 'starting', 'failed'];
const HANDOFF_STATUSES = ['requested', 'accepted', 'none'];
const PROMPT_CHARACTER_LIMIT = 50000;
const TOOL_PAYLOAD_CLASS =
  'm-0 max-h-48 overflow-auto rounded bg-n-solid-1 p-2 whitespace-pre-wrap';

const DEFAULT_AGENT = {
  name: 'Voice Assistant',
  greeting: 'Merhaba, size nasil yardimci olabilirim?',
  prompt:
    'Yalnizca dogal Istanbul Turkcesiyle konus. Kisa, net ve sakin musteri destek cevaplari ver.',
  knowledge_source_ids: [],
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
    enabled: Array.from(
      new Set(['human_handoff', 'end_customer_call', ...(tools.enabled || [])])
    ).filter(Boolean),
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

const normalizeKnowledgeSourceIds = sourceIds =>
  Array.from(new Set(sourceIds || []))
    .map(Number)
    .sort((first, second) => first - second);

const store = useStore();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const settings = ref([]);
const voiceAgents = ref([]);
const voiceUsage = ref(null);
const improvementUsage = ref(null);
const recordings = ref([]);
const telephonyReadiness = ref({ configured: false, numbers: [] });
const selectedVoiceAgentId = ref('');
const selectedTestInboxId = ref('');
const callerName = ref('Test caller');
const callerNumber = ref('+900000000000');
const activeTab = ref('agents');
const currentCall = ref(null);
const isLoading = ref(false);
const isLoadingRecordings = ref(false);
const isSavingAgent = ref(false);
const isPublishingAgent = ref(false);
const isActivatingAgent = ref(false);
const releaseHistoryRef = ref(null);
const publishDialogRef = ref(null);
const improvementCreditsRef = ref(null);
const isCreatingCall = ref(false);
const isEnding = ref(false);
const isRefreshing = ref(false);
const recordingFilters = ref({
  status: '',
  handoff_status: '',
  phone: '',
  limit: 25,
});

const agentForm = ref(clone(DEFAULT_AGENT));
const assignmentForm = ref({});
const editingVoiceAgentId = ref(null);
const savedAgentSnapshot = ref('');
const voiceSetupProfile = ref({
  goal: 'support',
  tone: 'friendly',
  businessContext: '',
  boundaries: '',
});

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
} = useVoiceSession({ call: currentCall });

const inboxes = useMapGetter('inboxes/getInboxes');
const teams = useMapGetter('teams/getTeams');

const tabs = computed(() => [
  { label: t('VOICE_AI.TABS.AGENTS'), value: 'agents' },
  { label: t('VOICE_AI.TABS.TEST'), value: 'test' },
  { label: t('VOICE_AI.TABS.CALLS'), value: 'calls' },
  { label: t('VOICE_AI.TABS.RECORDINGS'), value: 'recordings' },
  { label: t('VOICE_AI.TABS.USAGE'), value: 'usage' },
]);

const openKnowledgeLibrary = () =>
  router.push({ name: 'ai_knowledge_sources' });
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
const availableToolKeys = computed(() =>
  availableTools.value.map(tool => tool.key)
);
const normalizeToolsConfigForAvailableTools = toolsConfig => {
  const config = normalizeToolsConfig(toolsConfig);
  if (!availableToolKeys.value.length) return config;

  config.enabled = config.enabled.filter(key =>
    availableToolKeys.value.includes(key)
  );
  config.ikas_lookup_order.enabled =
    config.ikas_lookup_order.enabled &&
    config.enabled.includes('ikas_lookup_order');

  return config;
};

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
const shouldShowIkasToolStatus = computed(() => isIkasAvailable.value);

const voiceAccessEnabled = computed(() => voiceUsage.value?.enabled === true);
const isVoiceAccessDisabled = computed(
  () => Boolean(voiceUsage.value) && !voiceAccessEnabled.value
);
const promptLength = computed(() => agentForm.value.prompt?.length || 0);
const lifecycleStatus = computed(
  () => selectedVoiceAgent.value?.lifecycle_status || 'draft'
);
const isActiveAgent = computed(() => lifecycleStatus.value === 'active');
const hasPublishedVoiceRelease = computed(
  () => (selectedVoiceAgent.value?.published_revision || 0) > 0
);
const hasVoiceDraftChanges = computed(() =>
  Boolean(selectedVoiceAgent.value?.draft_changes)
);
const showVoicePublishAction = computed(
  () => !hasPublishedVoiceRelease.value || hasVoiceDraftChanges.value
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
const improvementCreditsExhausted = computed(
  () => improvementUsage.value?.status === 'exhausted'
);
const availableVoiceTestSeconds = computed(() => {
  if (hasActiveTestCall.value) {
    return currentCall.value?.test_duration_limit_seconds || null;
  }
  if (!improvementUsage.value || improvementUsage.value.unlimited) return null;

  const secondsPerCredit = improvementUsage.value.rates?.audio_seconds || 10;
  const accountMaximum =
    (voiceUsage.value?.max_call_duration_minutes || 15) * 60;
  return Math.min(
    improvementUsage.value.remaining_credits * secondsPerCredit,
    accountMaximum
  );
});
const voiceTestDurationText = computed(() => {
  const seconds = availableVoiceTestSeconds.value;
  if (!seconds) return '';
  if (seconds >= 60 && seconds % 60 === 0) {
    return t('VOICE_AI.SETUP.TEST_CREDIT_DURATION_MINUTES', {
      minutes: seconds / 60,
    });
  }

  return t('VOICE_AI.SETUP.TEST_CREDIT_DURATION_SECONDS', { seconds });
});
const canStartTest = computed(
  () =>
    voiceAccessEnabled.value &&
    Boolean(selectedTestInboxSetting.value) &&
    !isCreatingCall.value &&
    !improvementCreditsExhausted.value &&
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
const callAiStatus = computed(() => currentCall.value?.ai_status || '');
const hasAgentActivity = computed(
  () =>
    ['active', 'completed'].includes(callAiStatus.value) ||
    transcriptSegments.value.length > 0 ||
    testToolEvents.value.length > 0
);
const testSteps = computed(() => [
  {
    key: 'setup',
    label: t('VOICE_AI.TEST_STEPS.SETUP'),
    complete: Boolean(selectedTestInboxSetting.value),
  },
  {
    key: 'created',
    label: t('VOICE_AI.TEST_STEPS.CREATED'),
    complete: hasCall.value,
  },
  {
    key: 'joined',
    label: t('VOICE_AI.TEST_STEPS.JOINED'),
    complete: isConnected.value || hasAgentActivity.value,
  },
  {
    key: 'agent',
    label: t('VOICE_AI.TEST_STEPS.AGENT_ACTIVE'),
    complete: hasAgentActivity.value,
  },
  {
    key: 'ended',
    label: t('VOICE_AI.TEST_STEPS.ENDED'),
    complete: isCurrentCallTerminal.value,
  },
]);
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

const isMandatoryTool = toolKey =>
  ['human_handoff', 'end_customer_call'].includes(toolKey);

const capabilityLabel = toolKey => {
  if (toolKey === 'human_handoff') {
    return t('VOICE_AI.CAPABILITIES.HUMAN_HANDOFF.LABEL');
  }
  if (toolKey === 'ikas_lookup_order') {
    return t('VOICE_AI.CAPABILITIES.IKAS_LOOKUP_ORDER.LABEL');
  }
  if (toolKey === 'ikas_catalog_search') {
    return t('VOICE_AI.CAPABILITIES.IKAS_CATALOG_SEARCH.LABEL');
  }
  if (toolKey === 'end_customer_call') {
    return t('VOICE_AI.CAPABILITIES.END_CUSTOMER_CALL.LABEL');
  }
  return toolKey;
};

const capabilityDescription = toolKey => {
  if (toolKey === 'human_handoff') {
    return t('VOICE_AI.CAPABILITIES.HUMAN_HANDOFF.DESCRIPTION');
  }
  if (toolKey === 'ikas_lookup_order') {
    return t('VOICE_AI.CAPABILITIES.IKAS_LOOKUP_ORDER.DESCRIPTION');
  }
  if (toolKey === 'ikas_catalog_search') {
    return t('VOICE_AI.CAPABILITIES.IKAS_CATALOG_SEARCH.DESCRIPTION');
  }
  if (toolKey === 'end_customer_call') {
    return t('VOICE_AI.CAPABILITIES.END_CUSTOMER_CALL.DESCRIPTION');
  }
  return '';
};

const statusLabel = status => {
  if (status === 'active') return t('VOICE_AI.STATUS.ACTIVE');
  if (status === 'paused') return t('VOICE_AI.STATUS.PAUSED');
  return t('VOICE_AI.STATUS.DRAFT');
};

const readinessLabel = key => {
  if (key === 'greeting') return t('VOICE_AI.READINESS.GREETING');
  if (key === 'inbox') return t('VOICE_AI.READINESS.INBOX');
  if (key === 'test') return t('VOICE_AI.READINESS.TEST');
  if (key === 'phone') return t('VOICE_AI.READINESS.PHONE');
  return t('VOICE_AI.READINESS.INSTRUCTIONS');
};

const goalLabel = goal => {
  if (goal === 'sales') return t('VOICE_AI.CREATE.GOALS.SALES');
  if (goal === 'orders') return t('VOICE_AI.CREATE.GOALS.ORDERS');
  return t('VOICE_AI.CREATE.GOALS.SUPPORT');
};

const toneLabel = tone => {
  if (tone === 'professional') {
    return t('VOICE_AI.CREATE.TONES.PROFESSIONAL');
  }
  if (tone === 'concise') return t('VOICE_AI.CREATE.TONES.CONCISE');
  return t('VOICE_AI.CREATE.TONES.FRIENDLY');
};

const buildVoiceInstructions = () => {
  const goal = goalLabel(voiceSetupProfile.value.goal);
  const tone = toneLabel(voiceSetupProfile.value.tone);
  const lines = [
    `Role: You are ${agentForm.value.name || 'a voice assistant'} for customer calls.`,
    `Primary goal: ${goal}.`,
    `Tone: ${tone}. Speak naturally and keep answers easy to follow aloud.`,
  ];
  if (voiceSetupProfile.value.businessContext.trim()) {
    lines.push(
      `Business context: ${voiceSetupProfile.value.businessContext.trim()}`
    );
  }
  if (voiceSetupProfile.value.boundaries.trim()) {
    lines.push(`Boundaries: ${voiceSetupProfile.value.boundaries.trim()}`);
  }
  lines.push(
    'When a caller asks for a person or needs human judgment, request human support.'
  );
  agentForm.value.prompt = lines.join('\n\n');
};
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

const compactParams = params =>
  Object.fromEntries(
    Object.entries(params).filter(
      ([, value]) => value !== '' && value !== null && value !== undefined
    )
  );

const assignmentPayload = () =>
  assignmentRows.value
    .filter(row => row.form?.assigned)
    .map(row => ({
      inbox_id: row.inbox.id,
      fallback_team_id: row.form.fallback_team_id || null,
      recording_enabled: Boolean(row.form.recording_enabled),
    }));

const editableAgentPayload = () => ({
  id: editingVoiceAgentId.value || null,
  name: agentForm.value.name || '',
  greeting: agentForm.value.greeting || '',
  prompt: agentForm.value.prompt || '',
  knowledge_source_ids: normalizeKnowledgeSourceIds(
    agentForm.value.knowledge_source_ids
  ),
  tools_config: normalizeToolsConfigForAvailableTools(
    agentForm.value.tools_config
  ),
  inbox_settings: assignmentPayload(),
});

const currentAgentSnapshot = computed(() =>
  JSON.stringify(editableAgentPayload())
);
const hasUnsavedAgentChanges = computed(
  () =>
    Boolean(savedAgentSnapshot.value) &&
    currentAgentSnapshot.value !== savedAgentSnapshot.value
);
const canSaveAgent = computed(
  () =>
    voiceAccessEnabled.value &&
    !isSavingAgent.value &&
    Boolean(agentForm.value.name?.trim()) &&
    promptLength.value <= PROMPT_CHARACTER_LIMIT &&
    (!editingVoiceAgentId.value || hasUnsavedAgentChanges.value)
);

const resetAgentSnapshot = async () => {
  await nextTick();
  savedAgentSnapshot.value = currentAgentSnapshot.value;
};

const confirmDiscardAgentChanges = () =>
  !hasUnsavedAgentChanges.value ||
  // eslint-disable-next-line no-alert
  window.confirm(t('VOICE_AI.AGENTS.UNSAVED_CHANGES'));

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
    };
  });
  assignmentForm.value = rows;
};

const syncAgentForm = agent => {
  if (!agent) {
    editingVoiceAgentId.value = null;
    agentForm.value = clone(DEFAULT_AGENT);
    syncAssignmentForm(null);
    resetAgentSnapshot();
    return;
  }

  editingVoiceAgentId.value = agent?.id || null;
  agentForm.value = {
    ...clone(DEFAULT_AGENT),
    ...agent,
    knowledge_source_ids: normalizeKnowledgeSourceIds(
      agent?.knowledge_source_ids
    ),
    tools_config: normalizeToolsConfigForAvailableTools(agent?.tools_config),
    inbox_settings: agent?.inbox_settings || [],
  };
  syncAssignmentForm(agent);
  resetAgentSnapshot();
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

const fetchRecordings = async () => {
  if (!voiceAccessEnabled.value || isLoadingRecordings.value) return;

  isLoadingRecordings.value = true;
  try {
    const response = await VoiceAPI.getRecordings(
      compactParams(recordingFilters.value)
    );
    recordings.value = response.data || [];
  } catch {
    useAlert(t('VOICE_AI.RECORDINGS.LOAD_ERROR'));
  } finally {
    isLoadingRecordings.value = false;
  }
};

const loadData = async () => {
  isLoading.value = true;
  try {
    await Promise.all([
      store.dispatch('inboxes/get'),
      store.dispatch('teams/get'),
    ]);
    const [agentResponse, settingsResponse, usageResponse, telephonyResponse] =
      await Promise.all([
        VoiceAPI.getAgents(),
        VoiceAPI.getSettings(),
        VoiceAPI.getUsage(),
        VoiceAPI.getTelephonyReadiness(),
      ]);
    voiceAgents.value = agentResponse.data?.payload || [];
    settings.value = settingsResponse.data?.payload || [];
    voiceUsage.value = usageResponse.data || null;
    telephonyReadiness.value = telephonyResponse.data || {
      configured: false,
      numbers: [],
    };
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

const saveVoiceAgent = async () => {
  if (!canSaveAgent.value) return;
  isSavingAgent.value = true;
  try {
    const payload = {
      name: agentForm.value.name,
      greeting: agentForm.value.greeting,
      prompt: agentForm.value.prompt,
      knowledge_source_ids: normalizeKnowledgeSourceIds(
        agentForm.value.knowledge_source_ids
      ),
      tools_config: normalizeToolsConfigForAvailableTools(
        agentForm.value.tools_config
      ),
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

const replaceVoiceAgent = saved => {
  voiceAgents.value = [
    ...voiceAgents.value.filter(agent => agent.id !== saved.id),
    saved,
  ].sort((a, b) => a.id - b.id);
  selectedVoiceAgentId.value = saved.id;
};

const openPublishDialog = () => publishDialogRef.value?.open();

const publishVoiceAgent = async ({ activate }) => {
  if (!selectedVoiceAgent.value?.readiness?.can_publish) return;
  isPublishingAgent.value = true;
  try {
    const response = await VoiceAPI.publishAgent(selectedVoiceAgent.value.id, {
      activate,
    });
    replaceVoiceAgent(response.data);
    syncAgentForm(response.data);
    publishDialogRef.value?.close();
    useAlert(
      activate
        ? t('VOICE_AI.AGENTS.PUBLISH_SUCCESS')
        : t('VOICE_AI.AGENTS.PUBLISH_PAUSED_SUCCESS')
    );
  } catch (error) {
    useAlert(error.response?.data?.error || t('VOICE_AI.AGENTS.PUBLISH_ERROR'));
  } finally {
    isPublishingAgent.value = false;
  }
};

const activateVoiceAgent = async () => {
  isActivatingAgent.value = true;
  try {
    const response = await VoiceAPI.activateAgent(selectedVoiceAgent.value.id);
    replaceVoiceAgent(response.data);
    useAlert(t('VOICE_AI.AGENTS.ACTIVATE_SUCCESS'));
  } catch (error) {
    useAlert(
      error.response?.data?.error || t('VOICE_AI.AGENTS.ACTIVATE_ERROR')
    );
  } finally {
    isActivatingAgent.value = false;
  }
};

const pauseVoiceAgent = async () => {
  try {
    const response = await VoiceAPI.pauseAgent(selectedVoiceAgent.value.id);
    replaceVoiceAgent(response.data);
    useAlert(t('VOICE_AI.AGENTS.PAUSE_SUCCESS'));
  } catch (error) {
    useAlert(error.response?.data?.error || t('VOICE_AI.AGENTS.PAUSE_ERROR'));
  }
};

const openReleaseHistory = () => releaseHistoryRef.value?.open();

const refreshSelectedVoiceAgent = async () => {
  if (!selectedVoiceAgentId.value) return;
  const response = await VoiceAPI.getAgent(selectedVoiceAgentId.value);
  replaceVoiceAgent(response.data);
};

const handleReleaseRestored = async () => {
  await refreshSelectedVoiceAgent();
  syncAgentForm(selectedVoiceAgent.value);
};

const createNewVoiceAgent = () => {
  if (!voiceAccessEnabled.value) return;
  if (!confirmDiscardAgentChanges()) return;

  selectedVoiceAgentId.value = '';
  syncAgentForm(null);
  activeTab.value = 'agents';
};

const editVoiceAgent = agent => {
  if (
    Number(editingVoiceAgentId.value) !== Number(agent.id) &&
    !confirmDiscardAgentChanges()
  ) {
    return;
  }

  selectedVoiceAgentId.value = agent.id;
  syncAgentForm(agent);
  ensureSelectedTestInbox();
  activeTab.value = 'agents';
};

const changeTab = tab => {
  if (tab.value === activeTab.value) return;
  if (activeTab.value === 'agents' && !confirmDiscardAgentChanges()) return;

  activeTab.value = tab.value;
  router.replace({ query: { ...route.query, section: tab.value } });
  if (tab.value === 'recordings') {
    fetchRecordings();
  }
};

const toggleTool = toolKey => {
  if (isMandatoryTool(toolKey)) return;
  if (!availableToolKeys.value.includes(toolKey)) return;

  const enabled = new Set(agentForm.value.tools_config.enabled);
  if (enabled.has(toolKey)) {
    enabled.delete(toolKey);
  } else {
    enabled.add(toolKey);
  }
  agentForm.value = {
    ...agentForm.value,
    tools_config: {
      ...normalizeToolsConfigForAvailableTools(agentForm.value.tools_config),
      enabled: Array.from(enabled).filter(key =>
        availableToolKeys.value.includes(key)
      ),
      ikas_lookup_order: {
        ...agentForm.value.tools_config.ikas_lookup_order,
        enabled: enabled.has('ikas_lookup_order'),
      },
    },
  };
};

const handleImprovementUsageLoaded = usage => {
  improvementUsage.value = usage;
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
    await improvementCreditsRef.value?.refresh();
    disconnectRoom();
    useAlert(t('VOICE_AI.SETUP.START_SUCCESS'));
  } catch (error) {
    if (error.response?.data?.usage) {
      improvementUsage.value = error.response.data.usage;
    }
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

const formatDurationSeconds = seconds => {
  if (seconds == null) return '-';

  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds % 60;
  return `${minutes}:${String(remainingSeconds).padStart(2, '0')}`;
};

const recordingCallSummary = recording => recording.call?.summary?.text || '';

const testStepClass = step => {
  if (step.complete) return 'border-n-teal-5 bg-n-teal-2 text-n-teal-11';
  const firstIncomplete = testSteps.value.find(item => !item.complete);
  if (firstIncomplete?.key === step.key) {
    return 'border-n-amber-5 bg-n-amber-2 text-n-amber-11';
  }
  return 'border-n-weak bg-n-alpha-2 text-n-slate-11';
};

const endCall = async () => {
  if (!canUseLiveControls.value || isEnding.value) return;
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('VOICE_AI.SESSION.END_CALL_CONFIRM'))) return;

  isEnding.value = true;
  try {
    const response = await VoiceAPI.endCall(currentCall.value.id, {
      end_reason: 'browser_test_ended',
    });
    currentCall.value = response.data;
    disconnectRoom();
    await refreshUsage();
    await improvementCreditsRef.value?.refresh();
    useAlert(t('VOICE_AI.SESSION.END_SUCCESS'));
  } catch {
    useAlert(t('VOICE_AI.SESSION.ACTION_ERROR'));
  } finally {
    isEnding.value = false;
  }
};

const onTranscriptSegment = async data => {
  if (!currentCall.value || data.call_id !== currentCall.value.id) return;
  const segments = currentCall.value.transcript_segments || [];
  if (segments.some(segment => segment.id === data.segment.id)) return;
  currentCall.value = {
    ...currentCall.value,
    transcript_segments: [...segments, data.segment],
  };
  if (data.segment.role === 'ai') {
    await refreshSelectedVoiceAgent();
  }
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

const onBeforeUnload = event => {
  if (!hasUnsavedAgentChanges.value) return;

  event.preventDefault();
  event.returnValue = '';
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

watch(currentCallStatus, status => {
  if (TERMINAL_CALL_STATUSES.includes(status)) disconnectRoom();
});

watch(
  () => route.query.section,
  section => {
    if (tabs.value.some(tab => tab.value === section)) {
      activeTab.value = section;
    } else if (section) {
      activeTab.value = 'agents';
      router.replace({ query: { ...route.query, section: 'agents' } });
    }
  }
);

onBeforeRouteLeave(() => confirmDiscardAgentChanges());

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
  if (tabs.value.some(tab => tab.value === route.query.section)) {
    activeTab.value = route.query.section;
  } else if (route.query.section) {
    router.replace({ query: { ...route.query, section: 'agents' } });
  }
  loadData();
  subscribeToVoiceEvents();
  window.addEventListener('beforeunload', onBeforeUnload);
});
onBeforeUnmount(() => {
  unsubscribeFromVoiceEvents();
  window.removeEventListener('beforeunload', onBeforeUnload);
});
</script>

<template>
  <SettingsLayout :is-loading="isLoading">
    <template #header>
      <BaseSettingsHeader
        :title="t('VOICE_AI.HEADER')"
        :description="t('VOICE_AI.DESCRIPTION')"
        feature-name="voice_ai"
      >
        <template #actions>
          <Button
            icon="i-lucide-library"
            variant="outline"
            color="slate"
            :label="t('AI_KNOWLEDGE.ACTIONS.MANAGE')"
            @click="openKnowledgeLibrary"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="flex flex-col gap-6">
        <ResponsiveTabNavigation
          :tabs="tabs"
          :active-tab-index="activeTabIndex"
          :aria-label="t('VOICE_AI.TABS.LABEL')"
          @tab-changed="changeTab"
        />

        <section
          v-if="activeTab === 'agents'"
          class="grid grid-cols-1 gap-6 xl:grid-cols-[320px_minmax(0,1fr)]"
        >
          <aside
            class="flex max-h-[calc(100vh-12rem)] flex-col rounded-xl border border-n-weak bg-n-solid-1 p-4"
          >
            <div class="mb-4 flex flex-col gap-3">
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
                class="w-full"
                :disabled="!voiceAccessEnabled"
                @click="createNewVoiceAgent"
              />
            </div>
            <div v-if="!voiceAgents.length" class="text-sm text-n-slate-11">
              {{ t('VOICE_AI.AGENTS.EMPTY') }}
            </div>
            <div v-else class="flex flex-col gap-2 overflow-y-auto pr-1">
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
                <span
                  class="mt-2 inline-flex w-fit rounded-md px-2 py-1 text-xs font-medium"
                  :class="{
                    'bg-n-teal-3 text-n-teal-11':
                      agent.lifecycle_status === 'active',
                    'bg-n-amber-3 text-n-amber-11':
                      agent.lifecycle_status === 'paused',
                    'bg-n-slate-3 text-n-slate-11':
                      agent.lifecycle_status === 'draft',
                  }"
                >
                  {{ statusLabel(agent.lifecycle_status) }}
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

          <div class="flex min-w-0 flex-col gap-5">
            <div
              class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between"
            >
              <div>
                <div class="flex flex-wrap items-center gap-2">
                  <h2 class="m-0 text-heading-2 text-n-slate-12">
                    {{ t('VOICE_AI.AGENTS.EDITOR_TITLE') }}
                  </h2>
                  <span
                    v-if="editingVoiceAgentId"
                    class="rounded-md px-2 py-1 text-xs font-medium"
                    :class="
                      isActiveAgent
                        ? 'bg-n-teal-3 text-n-teal-11'
                        : lifecycleStatus === 'paused'
                          ? 'bg-n-amber-3 text-n-amber-11'
                          : 'bg-n-slate-3 text-n-slate-11'
                    "
                  >
                    {{ statusLabel(lifecycleStatus) }}
                  </span>
                </div>
                <p class="mb-0 mt-1 text-sm text-n-slate-11">
                  {{ t('VOICE_AI.AGENTS.EDITOR_DESCRIPTION') }}
                </p>
              </div>
              <div
                v-if="editingVoiceAgentId"
                class="flex flex-wrap justify-end gap-2"
              >
                <Button
                  v-if="hasPublishedVoiceRelease"
                  icon="i-lucide-history"
                  variant="outline"
                  color="slate"
                  :label="t('AI_ASSISTANT.RELEASE_HISTORY.OPEN')"
                  @click="openReleaseHistory"
                />
                <Button
                  v-if="isActiveAgent"
                  icon="i-lucide-pause"
                  variant="outline"
                  color="amber"
                  :label="t('VOICE_AI.AGENTS.PAUSE')"
                  @click="pauseVoiceAgent"
                />
                <Button
                  v-else-if="hasPublishedVoiceRelease"
                  icon="i-lucide-play"
                  variant="outline"
                  color="teal"
                  :label="t('VOICE_AI.AGENTS.ACTIVATE')"
                  :is-loading="isActivatingAgent"
                  @click="activateVoiceAgent"
                />
                <Button
                  v-if="showVoicePublishAction"
                  icon="i-lucide-rocket"
                  :label="
                    hasPublishedVoiceRelease
                      ? t('VOICE_AI.AGENTS.PUBLISH_UPDATE')
                      : t('VOICE_AI.AGENTS.PUBLISH')
                  "
                  :disabled="
                    !selectedVoiceAgent?.readiness?.can_publish ||
                    hasUnsavedAgentChanges
                  "
                  @click="openPublishDialog"
                />
              </div>
            </div>

            <div
              v-if="isActiveAgent"
              class="rounded-lg border border-n-teal-5 bg-n-teal-2 p-3 text-sm text-n-teal-11"
            >
              {{ t('VOICE_AI.AGENTS.LIVE_EDIT_NOTICE') }}
            </div>

            <section
              v-if="!editingVoiceAgentId"
              class="flex flex-col gap-4 rounded-lg border border-n-weak p-4"
            >
              <div>
                <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                  {{ t('VOICE_AI.CREATE.TITLE') }}
                </h3>
                <p class="mb-0 mt-1 text-sm text-n-slate-11">
                  {{ t('VOICE_AI.CREATE.DESCRIPTION') }}
                </p>
              </div>
              <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                <label
                  class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
                >
                  {{ t('VOICE_AI.CREATE.GOAL') }}
                  <select
                    v-model="voiceSetupProfile.goal"
                    class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal"
                  >
                    <option value="support">
                      {{ t('VOICE_AI.CREATE.GOALS.SUPPORT') }}
                    </option>
                    <option value="sales">
                      {{ t('VOICE_AI.CREATE.GOALS.SALES') }}
                    </option>
                    <option value="orders">
                      {{ t('VOICE_AI.CREATE.GOALS.ORDERS') }}
                    </option>
                  </select>
                </label>
                <label
                  class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
                >
                  {{ t('VOICE_AI.CREATE.TONE') }}
                  <select
                    v-model="voiceSetupProfile.tone"
                    class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal"
                  >
                    <option value="friendly">
                      {{ t('VOICE_AI.CREATE.TONES.FRIENDLY') }}
                    </option>
                    <option value="professional">
                      {{ t('VOICE_AI.CREATE.TONES.PROFESSIONAL') }}
                    </option>
                    <option value="concise">
                      {{ t('VOICE_AI.CREATE.TONES.CONCISE') }}
                    </option>
                  </select>
                </label>
              </div>
              <label
                class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
              >
                {{ t('VOICE_AI.CREATE.BUSINESS_CONTEXT') }}
                <textarea
                  v-model="voiceSetupProfile.businessContext"
                  rows="3"
                  class="rounded-lg border border-n-weak bg-n-alpha-1 p-3 font-normal"
                />
              </label>
              <label
                class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
              >
                {{ t('VOICE_AI.CREATE.BOUNDARIES') }}
                <textarea
                  v-model="voiceSetupProfile.boundaries"
                  rows="3"
                  class="rounded-lg border border-n-weak bg-n-alpha-1 p-3 font-normal"
                />
              </label>
              <Button
                icon="i-lucide-wand-sparkles"
                variant="outline"
                color="slate"
                class="w-fit"
                :label="t('VOICE_AI.CREATE.BUILD_INSTRUCTIONS')"
                @click="buildVoiceInstructions"
              />
            </section>

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

            <label class="flex flex-col gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('VOICE_AI.AGENTS.PROMPT') }}
              </span>
              <textarea
                v-model="agentForm.prompt"
                rows="10"
                :maxlength="PROMPT_CHARACTER_LIMIT"
                :disabled="!voiceAccessEnabled"
                class="rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 resize-y"
              />
              <span class="text-right text-xs text-n-slate-10">
                {{
                  t('VOICE_AI.AGENTS.PROMPT_CHAR_COUNT', {
                    count: promptLength,
                    limit: PROMPT_CHARACTER_LIMIT,
                  })
                }}
              </span>
            </label>

            <KnowledgeSourceSelector
              v-model="agentForm.knowledge_source_ids"
              :disabled="!voiceAccessEnabled"
            />

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
                    v-if="!isMandatoryTool(tool.key)"
                    type="checkbox"
                    class="mt-1 h-4 w-4 rounded border-n-slate-6 text-n-brand"
                    :checked="isToolEnabled(tool.key)"
                    :disabled="!voiceAccessEnabled"
                    @change="toggleTool(tool.key)"
                  />
                  <span class="min-w-0">
                    <span class="block text-sm font-medium text-n-slate-12">
                      {{ capabilityLabel(tool.key) }}
                    </span>
                    <span class="mt-1 block text-xs text-n-slate-11">
                      {{ capabilityDescription(tool.key) }}
                    </span>
                  </span>
                  <span
                    v-if="isMandatoryTool(tool.key)"
                    class="ml-auto flex-shrink-0 rounded-md bg-n-teal-3 px-2 py-1 text-xs font-medium text-n-teal-11"
                  >
                    {{ t('VOICE_AI.CAPABILITIES.ALWAYS_AVAILABLE') }}
                  </span>
                </label>
              </div>
              <p
                v-if="shouldShowIkasToolStatus"
                class="mb-0 mt-3 text-xs text-n-slate-11"
              >
                {{
                  isIkasAvailable
                    ? isIkasCatalogReady
                      ? t('VOICE_AI.AGENTS.IKAS_READY')
                      : t('VOICE_AI.AGENTS.IKAS_CATALOG_NOT_SYNCED')
                    : t('VOICE_AI.AGENTS.IKAS_NOT_CONNECTED')
                }}
              </p>
            </div>

            <div
              class="rounded-lg border p-4"
              :class="
                telephonyReadiness.configured
                  ? 'border-n-teal-5 bg-n-teal-2'
                  : 'border-n-amber-5 bg-n-amber-2'
              "
            >
              <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                {{ t('VOICE_AI.PHONE_READINESS.TITLE') }}
              </h3>
              <p class="mb-0 mt-1 text-sm text-n-slate-11">
                {{
                  telephonyReadiness.configured
                    ? t('VOICE_AI.PHONE_READINESS.READY')
                    : t('VOICE_AI.PHONE_READINESS.MISSING')
                }}
              </p>
              <ul
                v-if="telephonyReadiness.numbers.length"
                class="mb-0 mt-3 list-none p-0 text-sm text-n-slate-12"
              >
                <li
                  v-for="number in telephonyReadiness.numbers"
                  :key="number.id"
                >
                  {{
                    t('VOICE_AI.PHONE_READINESS.NUMBER_STATUS', {
                      number: number.phone_number,
                      status: number.status,
                    })
                  }}
                </li>
              </ul>
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
                  class="grid grid-cols-1 gap-3 py-4 xl:grid-cols-[minmax(0,1fr)_180px_120px]"
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

                  <div class="flex items-center justify-between gap-3">
                    <span class="text-xs text-n-slate-11">
                      {{ t('VOICE_AI.SETUP.RECORDING') }}
                    </span>
                    <Switch
                      v-model="row.form.recording_enabled"
                      :aria-label="
                        t('VOICE_AI.ASSIGNMENTS.RECORDING_LABEL', {
                          inbox: row.inbox.name,
                        })
                      "
                      :disabled="!voiceAccessEnabled || !row.form.assigned"
                    />
                  </div>
                </div>
              </div>
            </div>

            <section
              v-if="selectedVoiceAgent?.readiness"
              class="rounded-lg border border-n-weak p-4"
              aria-labelledby="voice-readiness-title"
            >
              <h3
                id="voice-readiness-title"
                class="m-0 text-sm font-semibold text-n-slate-12"
              >
                {{ t('VOICE_AI.READINESS.TITLE') }}
              </h3>
              <p class="mb-0 mt-1 text-sm text-n-slate-11">
                {{ t('VOICE_AI.READINESS.DESCRIPTION') }}
              </p>
              <ul class="mb-0 mt-3 flex list-none flex-col gap-2 p-0">
                <li
                  v-for="check in selectedVoiceAgent.readiness.checks"
                  :key="check.key"
                  class="flex items-start gap-2 text-sm"
                >
                  <span
                    class="mt-0.5 size-4 flex-shrink-0"
                    :class="
                      check.complete
                        ? 'i-lucide-circle-check text-n-teal-10'
                        : 'i-lucide-circle text-n-slate-9'
                    "
                  />
                  <span class="text-n-slate-12">
                    {{ readinessLabel(check.key) }}
                    <span v-if="!check.blocking" class="text-n-slate-10">
                      {{ t('VOICE_AI.READINESS.OPTIONAL') }}
                    </span>
                  </span>
                </li>
              </ul>
            </section>

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

        <VoiceCallActivity
          v-if="activeTab === 'calls'"
          :voice-agents="voiceAgents"
        />

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

            <ImprovementCreditsSummary
              ref="improvementCreditsRef"
              @loaded="handleImprovementUsageLoaded"
            />
            <p v-if="voiceTestDurationText" class="m-0 text-xs text-n-slate-10">
              {{ voiceTestDurationText }}
            </p>

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

            <div class="grid grid-cols-1 gap-2 md:grid-cols-5">
              <div
                v-for="step in testSteps"
                :key="step.key"
                class="rounded-lg border px-3 py-2 text-xs font-medium"
                :class="testStepClass(step)"
              >
                {{ step.label }}
              </div>
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
                    ? selectedVoiceAgent?.name
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
              <dt class="text-n-slate-11">
                {{ t('VOICE_AI.SESSION.ASSISTANT') }}
              </dt>
              <dd class="truncate text-n-slate-12">
                {{ selectedVoiceAgent?.name || '-' }}
              </dd>
              <dt class="text-n-slate-11">
                {{ t('VOICE_AI.SESSION.INBOX') }}
              </dt>
              <dd class="truncate text-n-slate-12">
                {{ selectedTestInboxSetting?.inbox_name || '-' }}
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
            <div
              v-else
              class="mt-4 flex flex-col gap-3"
              role="log"
              aria-live="polite"
              aria-relevant="additions text"
            >
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
                  <div class="mb-1 flex items-center gap-3">
                    <span
                      class="text-sm font-medium text-n-slate-12 capitalize"
                    >
                      {{ item.role }}
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
          v-if="activeTab === 'recordings'"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-5"
        >
          <div
            class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between"
          >
            <div>
              <h2 class="m-0 text-heading-2 text-n-slate-12">
                {{ t('VOICE_AI.RECORDINGS.TITLE') }}
              </h2>
              <p class="m-0 mt-1 text-sm text-n-slate-11">
                {{ t('VOICE_AI.RECORDINGS.DESCRIPTION') }}
              </p>
            </div>
            <Button
              :label="t('VOICE_AI.RECORDINGS.REFRESH')"
              icon="i-lucide-refresh-cw"
              variant="outline"
              color="slate"
              :is-loading="isLoadingRecordings"
              :disabled="!voiceAccessEnabled"
              @click="fetchRecordings"
            />
          </div>

          <div
            class="mt-5 grid grid-cols-1 gap-3 md:grid-cols-[160px_160px_minmax(0,1fr)_120px]"
          >
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">
                {{ t('VOICE_AI.RECORDINGS.STATUS') }}
              </span>
              <select
                v-model="recordingFilters.status"
                class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12"
              >
                <option value="">{{ t('VOICE_AI.SETUP.NONE') }}</option>
                <option
                  v-for="statusOption in RECORDING_STATUSES"
                  :key="statusOption"
                  :value="statusOption"
                >
                  {{ statusOption }}
                </option>
              </select>
            </label>

            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">
                {{ t('VOICE_AI.RECORDINGS.HANDOFF') }}
              </span>
              <select
                v-model="recordingFilters.handoff_status"
                class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12"
              >
                <option value="">{{ t('VOICE_AI.SETUP.NONE') }}</option>
                <option
                  v-for="handoffOption in HANDOFF_STATUSES"
                  :key="handoffOption"
                  :value="handoffOption"
                >
                  {{ handoffOption }}
                </option>
              </select>
            </label>

            <Input
              v-model="recordingFilters.phone"
              :label="t('VOICE_AI.RECORDINGS.PHONE')"
            />

            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">
                {{ t('VOICE_AI.RECORDINGS.LIMIT') }}
              </span>
              <input
                v-model.number="recordingFilters.limit"
                type="number"
                min="1"
                max="100"
                class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12"
              />
            </label>
          </div>

          <div class="mt-4 flex justify-end">
            <Button
              :label="t('VOICE_AI.RECORDINGS.APPLY')"
              icon="i-lucide-search"
              :disabled="!voiceAccessEnabled"
              :is-loading="isLoadingRecordings"
              @click="fetchRecordings"
            />
          </div>

          <div
            v-if="!voiceAccessEnabled"
            class="mt-5 rounded-lg border border-n-slate-5 bg-n-slate-2 p-4 text-sm text-n-slate-11"
          >
            {{ t('VOICE_AI.AGENTS.DISABLED_BY_ADMIN') }}
          </div>
          <div
            v-else-if="!recordings.length"
            class="mt-5 rounded-lg bg-n-alpha-2 p-4 text-sm text-n-slate-11"
          >
            {{
              isLoadingRecordings
                ? t('VOICE_AI.RECORDINGS.LOADING')
                : t('VOICE_AI.RECORDINGS.EMPTY')
            }}
          </div>
          <div v-else class="mt-5 overflow-x-auto">
            <table class="min-w-full border-separate border-spacing-0 text-sm">
              <thead>
                <tr class="text-left text-xs text-n-slate-11">
                  <th class="border-b border-n-weak px-3 py-2 font-medium">
                    {{ t('VOICE_AI.RECORDINGS.CALL') }}
                  </th>
                  <th class="border-b border-n-weak px-3 py-2 font-medium">
                    {{ t('VOICE_AI.RECORDINGS.STATUS') }}
                  </th>
                  <th class="border-b border-n-weak px-3 py-2 font-medium">
                    {{ t('VOICE_AI.RECORDINGS.DURATION') }}
                  </th>
                  <th class="border-b border-n-weak px-3 py-2 font-medium">
                    {{ t('VOICE_AI.RECORDINGS.SUMMARY') }}
                  </th>
                  <th class="border-b border-n-weak px-3 py-2 font-medium">
                    {{ t('VOICE_AI.RECORDINGS.AUDIO') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="recording in recordings"
                  :key="recording.id"
                  class="align-top"
                >
                  <td class="border-b border-n-weak px-3 py-3">
                    <div class="font-medium text-n-slate-12">
                      {{
                        t('VOICE_AI.RECORDINGS.CALL_NUMBER', {
                          id:
                            recording.call?.conversation_id ||
                            recording.call?.id,
                        })
                      }}
                    </div>
                    <div class="mt-1 text-xs text-n-slate-11">
                      {{ recording.call?.from_number || '-' }}
                    </div>
                    <div class="text-xs text-n-slate-10">
                      {{ formatDateTime(recording.completed_at) }}
                    </div>
                  </td>
                  <td class="border-b border-n-weak px-3 py-3">
                    <div class="capitalize text-n-slate-12">
                      {{ recording.status }}
                    </div>
                    <div class="mt-1 text-xs text-n-slate-11">
                      {{ recording.call?.handoff_status || '-' }}
                    </div>
                  </td>
                  <td class="border-b border-n-weak px-3 py-3 text-n-slate-12">
                    {{ formatDurationSeconds(recording.duration_seconds) }}
                  </td>
                  <td class="max-w-md border-b border-n-weak px-3 py-3">
                    <p
                      v-if="recordingCallSummary(recording)"
                      class="m-0 line-clamp-3 text-n-slate-12"
                    >
                      {{ recordingCallSummary(recording) }}
                    </p>
                    <span v-else class="text-n-slate-10">
                      {{ t('VOICE_AI.RECORDINGS.NO_VALUE') }}
                    </span>
                  </td>
                  <td class="border-b border-n-weak px-3 py-3">
                    <audio
                      v-if="recording.url"
                      class="w-56 max-w-full"
                      controls
                      :src="recording.url"
                    />
                    <span v-else class="text-xs text-n-slate-10">
                      {{ t('VOICE_AI.RECORDINGS.NO_AUDIO') }}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
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
  <AssistantReleaseHistoryDialog
    v-if="selectedVoiceAgent?.id"
    ref="releaseHistoryRef"
    assistant-type="voice"
    :assistant-id="selectedVoiceAgent.id"
    :current-release-id="selectedVoiceAgent.current_release?.id"
    @restored="handleReleaseRestored"
  />
  <VoicePublishDialog
    v-if="selectedVoiceAgent?.id"
    ref="publishDialogRef"
    :voice-agent="selectedVoiceAgent"
    :is-publishing="isPublishingAgent"
    @confirm="publishVoiceAgent"
  />
</template>
