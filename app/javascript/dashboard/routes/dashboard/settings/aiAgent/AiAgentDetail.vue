<script setup>
import { ref, computed, nextTick, onMounted, watch } from 'vue';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TestConversationLayout from './components/TestConversationLayout.vue';
import InstructionWorkspace from './components/InstructionWorkspace.vue';
import ImproveWorkspace from './components/ImproveWorkspace.vue';
import AssistantStatusBadge from './components/AssistantStatusBadge.vue';
import ReadinessChecklist from './components/ReadinessChecklist.vue';
import AssistantReleaseHistoryDialog from './components/AssistantReleaseHistoryDialog.vue';
import KnowledgeSourceSelector from './components/KnowledgeSourceSelector.vue';
import ResponsiveTabNavigation from '../components/ResponsiveTabNavigation.vue';
import {
  hasInstructionContent,
  instructionContentLength,
  instructionDocumentForAgent,
  normalizeInstructionDocument,
} from './helpers/instructionDocument';

const defaultToolsState = () => ({
  enabled: ['human_handoff'],
  human_handoff: {
    allowed_labels: [],
  },
  ikas_lookup_order: {
    enabled: false,
  },
  ikas_catalog_search: {},
});

const normalizeToolsState = toolsConfig => {
  const tools = toolsConfig || {};

  return {
    enabled: Array.from(
      new Set(['human_handoff', ...(tools.enabled || [])])
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
const { currentAccount } = useAccount();

const agentId = computed(() => Number(route.params.id));

const aiAgent = useMapGetter('aiAgent/getAiAgent');
const uiFlags = useMapGetter('aiAgent/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');
const accountWebsite = computed(
  () => currentAccount.value?.custom_attributes?.website || ''
);

const isSaving = ref(false);
const releaseHistoryRef = ref(null);
const inboxError = ref('');
const activeTab = computed(() => {
  if (route.name === 'ai_agent_test') return 'test';
  if (route.name === 'ai_agent_knowledge') return 'knowledge';
  if (
    ['ai_agent_evaluations', 'ai_agent_learning_suggestions'].includes(
      route.name
    )
  ) {
    return 'improve';
  }
  if (route.name === 'ai_agent_detail') return 'connections';
  return 'instructions';
});
const improveMode = computed(() =>
  route.name === 'ai_agent_learning_suggestions' ? 'learnings' : 'evaluations'
);

// Local form state - initialized from store on load
const formState = ref({
  name: '',
  instructions: normalizeInstructionDocument(),
  knowledge_source_ids: [],
  inbox_ids: [],
  tools: defaultToolsState(),
});

const isInstructionsDirty = computed(() => {
  const persisted = instructionDocumentForAgent(aiAgent.value);
  return (
    JSON.stringify(
      normalizeInstructionDocument(formState.value.instructions)
    ) !== JSON.stringify(persisted)
  );
});

const isKnowledgeDirty = computed(
  () =>
    JSON.stringify(
      normalizeKnowledgeSourceIds(formState.value.knowledge_source_ids)
    ) !==
    JSON.stringify(
      normalizeKnowledgeSourceIds(aiAgent.value?.knowledge_source_ids)
    )
);

const isConnectionsDirty = computed(() => {
  const record = aiAgent.value;
  if (!record) {
    return (
      formState.value.name !== '' ||
      formState.value.inbox_ids.length !== 0 ||
      JSON.stringify(formState.value.tools) !==
        JSON.stringify(defaultToolsState())
    );
  }
  return (
    formState.value.name !== (record.name || '') ||
    JSON.stringify(formState.value.inbox_ids) !==
      JSON.stringify(record.agent_bot?.inbox_ids || []) ||
    JSON.stringify(formState.value.tools) !==
      JSON.stringify(normalizeToolsState(record.tools_config))
  );
});

const isFormDirty = computed(
  () =>
    isInstructionsDirty.value ||
    isKnowledgeDirty.value ||
    isConnectionsDirty.value
);

const tabs = computed(() => [
  { label: t('AI_AGENT.TABS.INSTRUCTIONS'), value: 'instructions' },
  { label: t('AI_AGENT.TABS.KNOWLEDGE'), value: 'knowledge' },
  { label: t('AI_AGENT.TABS.CONNECTIONS'), value: 'connections' },
  { label: t('AI_AGENT.TABS.TEST_HISTORY'), value: 'test' },
  { label: t('AI_AGENT.TABS.IMPROVE'), value: 'improve' },
]);

const activeTabIndex = computed(() =>
  tabs.value.findIndex(tab => tab.value === activeTab.value)
);

const persistedInboxIds = computed(() => {
  return aiAgent.value?.agent_bot?.inbox_ids || [];
});

const inboxList = computed(() => {
  if (aiAgent.value?.available_inboxes?.length) {
    return aiAgent.value.available_inboxes;
  }

  return (inboxes.value || []).map(inbox => ({
    ...inbox,
    available: true,
    owned_by_current_ai_agent: persistedInboxIds.value.includes(inbox.id),
    conflicting: false,
    owner_name: null,
  }));
});

const simulatorDisabledMessageKey = computed(() => {
  if (!aiAgent.value?.prompt?.trim()) {
    return 'AI_AGENT.TEST_CONVERSATIONS.ADD_PROMPT_BEFORE_TESTING';
  }

  return null;
});

const isSimulatorDisabled = computed(() => {
  return Boolean(simulatorDisabledMessageKey.value);
});

const lifecycleStatus = computed(
  () => aiAgent.value?.lifecycle_status || 'draft'
);
const isActive = computed(() => lifecycleStatus.value === 'active');
const hasPublishedRelease = computed(
  () => (aiAgent.value?.published_revision || 0) > 0
);
const hasDraftChanges = computed(() => Boolean(aiAgent.value?.draft_changes));

const showPublishAction = computed(
  () => !isActive.value || hasDraftChanges.value
);

const publishActionLabel = computed(() => {
  if (isActive.value) return t('AI_ASSISTANT.ACTIONS.PUBLISH_UPDATE');
  if (lifecycleStatus.value === 'paused' && !hasDraftChanges.value) {
    return t('AI_ASSISTANT.ACTIONS.RESUME');
  }

  return t('AI_ASSISTANT.ACTIONS.PUBLISH');
});

const releaseNotice = computed(() => {
  if (!hasPublishedRelease.value) return null;

  if (isActive.value && hasDraftChanges.value) {
    return {
      icon: 'i-lucide-file-clock',
      classes: 'border-n-amber-5 bg-n-amber-2 text-n-amber-11',
      message: t('AI_ASSISTANT.RELEASE.PENDING', {
        version: aiAgent.value.published_revision,
      }),
    };
  }

  if (isActive.value) {
    return {
      icon: 'i-lucide-shield-check',
      classes: 'border-n-teal-5 bg-n-teal-2 text-n-teal-11',
      message: t('AI_ASSISTANT.RELEASE.LIVE', {
        version: aiAgent.value.published_revision,
      }),
    };
  }

  return {
    icon: 'i-lucide-circle-pause',
    classes: 'border-n-slate-5 bg-n-slate-2 text-n-slate-11',
    message: t('AI_ASSISTANT.RELEASE.PAUSED', {
      version: aiAgent.value.published_revision,
    }),
  };
});

const simulatorDisabledMessage = computed(() => {
  return simulatorDisabledMessageKey.value
    ? t(simulatorDisabledMessageKey.value)
    : '';
});

const isCurrentTabDirty = computed(() => {
  if (activeTab.value === 'instructions') return isInstructionsDirty.value;
  if (activeTab.value === 'knowledge') return isKnowledgeDirty.value;
  if (activeTab.value === 'connections') return isConnectionsDirty.value;

  return false;
});

const isSaveDisabled = computed(() => {
  if (isSaving.value || !isCurrentTabDirty.value) return true;
  if (activeTab.value !== 'instructions') return false;

  return (
    !hasInstructionContent(formState.value.instructions) ||
    instructionContentLength(formState.value.instructions) > 50000
  );
});

const availableTools = computed(() => aiAgent.value?.available_tools || []);

const handoffLabelOptions = computed(() => {
  return (labels.value || []).map(label => ({
    value: label.title,
    label: label.title,
  }));
});

const ikasIntegration = computed(() => {
  return (
    aiAgent.value?.ikas_integration || {
      feature_enabled: false,
      state: 'disabled',
      can_connect: false,
    }
  );
});

const isIkasAvailable = computed(() => {
  return (
    ikasIntegration.value.feature_enabled &&
    ikasIntegration.value.state === 'connected'
  );
});

const isIkasCatalogReady = computed(() => {
  return ikasIntegration.value.catalog_sync?.status === 'completed';
});

function syncFormState() {
  const record = aiAgent.value;
  if (record) {
    formState.value = {
      name: record.name || '',
      instructions: instructionDocumentForAgent(record),
      knowledge_source_ids: normalizeKnowledgeSourceIds(
        record.knowledge_source_ids
      ),
      inbox_ids: record.agent_bot?.inbox_ids || [],
      tools: normalizeToolsState(record.tools_config),
    };
  } else {
    formState.value = {
      name: '',
      instructions: normalizeInstructionDocument(),
      knowledge_source_ids: [],
      inbox_ids: [],
      tools: defaultToolsState(),
    };
  }
}

const isToolEnabled = toolKey =>
  formState.value.tools.enabled.includes(toolKey);

const toggleTool = toolKey => {
  if (toolKey === 'human_handoff') {
    return;
  }

  const enabled = new Set(formState.value.tools.enabled);
  if (enabled.has(toolKey)) {
    enabled.delete(toolKey);
  } else {
    enabled.add(toolKey);
  }

  formState.value = {
    ...formState.value,
    tools: {
      ...formState.value.tools,
      enabled: Array.from(enabled),
      ikas_lookup_order: {
        ...formState.value.tools.ikas_lookup_order,
        enabled:
          toolKey === 'ikas_lookup_order'
            ? enabled.has(toolKey)
            : formState.value.tools.ikas_lookup_order.enabled,
      },
      ikas_catalog_search: {},
    },
  };
};

const updateHandoffLabels = value => {
  formState.value = {
    ...formState.value,
    tools: {
      ...formState.value.tools,
      human_handoff: {
        ...formState.value.tools.human_handoff,
        allowed_labels: value,
      },
    },
  };
};

async function loadAgentDetail(aiAgentId) {
  if (!aiAgentId) return;

  await store.dispatch('labels/get');
  await store.dispatch('aiAgent/show', aiAgentId);
  store.dispatch('aiAgentTestConversations/reset');
  await store.dispatch('aiAgentTestConversations/get', {
    aiAgentId,
  });
  syncFormState();
}

const toggleInbox = inboxId => {
  const inbox = inboxList.value.find(item => item.id === inboxId);
  if (inbox?.conflicting) {
    return;
  }

  const ids = [...formState.value.inbox_ids];
  const index = ids.indexOf(inboxId);
  if (index === -1) {
    ids.push(inboxId);
  } else {
    ids.splice(index, 1);
  }
  formState.value = { ...formState.value, inbox_ids: ids };
};

const isInboxSelected = inboxId => {
  return formState.value.inbox_ids.includes(inboxId);
};

const getInboxStatusText = inbox => {
  if (inbox.conflicting && inbox.owner_name) {
    return t('AI_AGENT.INBOXES.ASSIGNED_TO', { owner: inbox.owner_name });
  }

  return inbox.channel_type;
};

const instructionSaveData = () => ({
  config: {
    instructions: normalizeInstructionDocument(formState.value.instructions),
  },
});

const knowledgeSaveData = () => ({
  knowledge_source_ids: normalizeKnowledgeSourceIds(
    formState.value.knowledge_source_ids
  ),
});

const connectionSaveData = () => {
  const tools = normalizeToolsState(formState.value.tools);
  return {
    name: formState.value.name,
    inbox_ids: formState.value.inbox_ids,
    config: {
      tools: {
        enabled: tools.enabled,
        human_handoff: {
          allowed_labels: tools.human_handoff.allowed_labels,
        },
        ikas_lookup_order: {
          enabled: tools.enabled.includes('ikas_lookup_order'),
        },
        ikas_catalog_search: {},
      },
    },
  };
};

const currentTabSaveData = () => {
  if (activeTab.value === 'instructions') return instructionSaveData();
  if (activeTab.value === 'knowledge') return knowledgeSaveData();

  return connectionSaveData();
};

const handleSave = async () => {
  isSaving.value = true;
  inboxError.value = '';
  const instructionsDraft = formState.value.instructions;
  const knowledgeDraft = formState.value.knowledge_source_ids;
  const connectionsDraft = {
    name: formState.value.name,
    inbox_ids: formState.value.inbox_ids,
    tools: formState.value.tools,
  };
  const preserveInstructionsDraft =
    activeTab.value !== 'instructions' && isInstructionsDirty.value;
  const preserveKnowledgeDraft =
    activeTab.value !== 'knowledge' && isKnowledgeDirty.value;
  const preserveConnectionsDraft =
    activeTab.value !== 'connections' && isConnectionsDirty.value;

  try {
    const payload = {
      id: agentId.value,
      data: currentTabSaveData(),
    };
    const result = await store.dispatch('aiAgent/update', payload);
    if (result?.id) {
      useAlert(t('AI_AGENT.SAVE.SUCCESS'));
      syncFormState();
      if (preserveInstructionsDraft) {
        formState.value.instructions = instructionsDraft;
      }
      if (preserveKnowledgeDraft) {
        formState.value.knowledge_source_ids = knowledgeDraft;
      }
      if (preserveConnectionsDraft) {
        formState.value = { ...formState.value, ...connectionsDraft };
      }
      return;
    }

    if (result?.error) {
      inboxError.value = result.error;
      useAlert(result.error);
    } else {
      useAlert(t('AI_AGENT.SAVE.ERROR'));
    }
  } catch {
    useAlert(t('AI_AGENT.SAVE.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const discardCurrentChanges = () => {
  if (activeTab.value === 'instructions') {
    formState.value.instructions = instructionDocumentForAgent(aiAgent.value);
    return;
  }
  if (activeTab.value === 'knowledge') {
    formState.value.knowledge_source_ids =
      aiAgent.value?.knowledge_source_ids || [];
    return;
  }

  formState.value = {
    ...formState.value,
    name: aiAgent.value?.name || '',
    inbox_ids: aiAgent.value?.agent_bot?.inbox_ids || [],
    tools: normalizeToolsState(aiAgent.value?.tools_config),
  };
  inboxError.value = '';
};

const goBack = () => {
  router.push({ name: 'ai_agents' });
};

onBeforeRouteLeave(to => {
  const detailRoutes = [
    'ai_agent_instructions',
    'ai_agent_knowledge',
    'ai_agent_detail',
    'ai_agent_test',
    'ai_agent_evaluations',
    'ai_agent_learning_suggestions',
  ];
  const staysOnCurrentAgent =
    detailRoutes.includes(to.name) && Number(to.params.id) === agentId.value;

  if (staysOnCurrentAgent) return true;

  if (isFormDirty.value) {
    const confirm = window.confirm(t('AI_AGENT.UNSAVED_CHANGES_WARNING'));
    if (!confirm) {
      return false;
    }
  }
  return true;
});

const handleTabChange = tab => {
  const routeNames = {
    instructions: 'ai_agent_instructions',
    knowledge: 'ai_agent_knowledge',
    connections: 'ai_agent_detail',
    test: 'ai_agent_test',
    improve: 'ai_agent_evaluations',
  };
  router.push({
    name: routeNames[tab.value],
    params: { id: agentId.value },
  });
};

const configureHandoff = async () => {
  await router.push({
    name: 'ai_agent_detail',
    params: { id: agentId.value },
    query: { section: 'human-handoff' },
  });
  await nextTick();
  document
    .getElementById('tool-human_handoff')
    ?.scrollIntoView({ behavior: 'smooth', block: 'center' });
};

const refreshAfterDraftTest = async () => {
  const draft = formState.value.instructions;
  await store.dispatch('aiAgent/refresh', agentId.value);
  formState.value.instructions = draft;
};

const refreshAfterLearningApplied = () => {
  formState.value.instructions = instructionDocumentForAgent(aiAgent.value);
};

const refreshAfterWebsiteImport = async () => {
  await store.dispatch('aiAgent/refresh', agentId.value);
  formState.value.instructions = instructionDocumentForAgent(aiAgent.value);
};

const handlePause = async () => {
  const result = await store.dispatch('aiAgent/pause', agentId.value);
  if (result?.id) {
    syncFormState();
    useAlert(t('AI_ASSISTANT.ACTIONS.PAUSED'));
  } else {
    useAlert(result?.error || t('AI_AGENT.SAVE.ERROR'));
  }
};

const handlePublish = async () => {
  let successMessage = t('AI_ASSISTANT.ACTIONS.PUBLISHED');
  if (isActive.value) {
    successMessage = t('AI_ASSISTANT.ACTIONS.UPDATED');
  } else if (lifecycleStatus.value === 'paused' && !hasDraftChanges.value) {
    successMessage = t('AI_ASSISTANT.ACTIONS.RESUMED');
  }
  const result = await store.dispatch('aiAgent/publish', agentId.value);
  if (result?.id) {
    syncFormState();
    useAlert(successMessage);
  } else {
    useAlert(result?.error || t('AI_ASSISTANT.ACTIONS.PUBLISH_ERROR'));
  }
};

const openReleaseHistory = () => releaseHistoryRef.value?.open();

const handleReleaseRestored = async () => {
  await store.dispatch('aiAgent/refresh', agentId.value);
  syncFormState();
};

onMounted(async () => {
  await loadAgentDetail(agentId.value);
});

watch(agentId, async (newAgentId, oldAgentId) => {
  if (!newAgentId || newAgentId === oldAgentId) {
    return;
  }

  await loadAgentDetail(newAgentId);
});
</script>

<template>
  <SettingsLayout :is-loading="uiFlags.isFetching">
    <template #header>
      <BaseSettingsHeader
        :title="aiAgent?.name || t('AI_AGENT.HEADER')"
        :description="t('AI_AGENT.DESCRIPTION')"
        :link-text="t('AI_AGENT.LEARN_MORE')"
        feature-name="ai_agent"
      >
        <template #actions>
          <div
            class="flex w-full flex-wrap items-center justify-end gap-2 sm:w-auto sm:gap-3"
          >
            <AssistantStatusBadge
              :status="lifecycleStatus"
              class="flex-shrink-0"
            />
            <Button
              v-if="hasPublishedRelease"
              icon="i-lucide-history"
              variant="outline"
              color="slate"
              class="flex-shrink-0"
              :label="t('AI_ASSISTANT.RELEASE_HISTORY.OPEN')"
              @click="openReleaseHistory"
            />
            <Button
              v-if="isActive"
              icon="i-lucide-pause"
              variant="outline"
              color="amber"
              class="flex-shrink-0"
              :label="t('AI_ASSISTANT.ACTIONS.PAUSE')"
              @click="handlePause"
            />
            <Button
              v-if="showPublishAction"
              icon="i-lucide-rocket"
              class="flex-shrink-0"
              :label="publishActionLabel"
              :disabled="!aiAgent?.readiness?.can_publish || isFormDirty"
              @click="handlePublish"
            />
            <Button
              v-tooltip="t('AI_AGENT.BACK')"
              icon="i-lucide-arrow-left"
              variant="outline"
              color="slate"
              class="flex-shrink-0"
              :aria-label="t('AI_AGENT.BACK')"
              @click="goBack"
            />
          </div>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <div class="flex flex-col gap-6">
        <div
          v-if="releaseNotice"
          class="flex items-start gap-3 rounded-lg border p-3 text-sm"
          :class="releaseNotice.classes"
        >
          <span
            aria-hidden="true"
            class="mt-0.5 size-4 flex-shrink-0"
            :class="releaseNotice.icon"
          />
          <p class="m-0">{{ releaseNotice.message }}</p>
        </div>
        <div
          class="z-20 flex flex-col gap-3 border-b border-n-weak bg-n-surface-1 py-3 sm:sticky sm:top-0 sm:flex-row sm:items-center sm:justify-between"
        >
          <ResponsiveTabNavigation
            :tabs="tabs"
            :active-tab-index="activeTabIndex"
            :aria-label="t('AI_AGENT.TABS.LABEL')"
            @tab-changed="handleTabChange"
          />
          <div
            v-if="
              ['instructions', 'knowledge', 'connections'].includes(activeTab)
            "
            class="flex justify-end gap-2"
          >
            <Button
              v-if="isCurrentTabDirty"
              :label="t('AI_AGENT.SAVE.DISCARD')"
              variant="ghost"
              color="slate"
              :disabled="isSaving"
              @click="discardCurrentChanges"
            />
            <Button
              :label="t('AI_AGENT.SAVE.BUTTON')"
              :is-loading="isSaving"
              :disabled="isSaveDisabled"
              @click="handleSave"
            />
          </div>
        </div>
        <InstructionWorkspace
          v-if="activeTab === 'instructions'"
          v-model="formState.instructions"
          :ai-agent-id="agentId"
          :is-dirty="isInstructionsDirty"
          :is-disabled="!hasInstructionContent(formState.instructions)"
          :default-website="accountWebsite"
          @configure-handoff="configureHandoff"
          @tested="refreshAfterDraftTest"
          @website-import-applied="refreshAfterWebsiteImport"
        />
        <div
          v-if="activeTab === 'knowledge'"
          class="grid grid-cols-1 items-start gap-8 lg:grid-cols-[minmax(0,1fr)_280px]"
        >
          <KnowledgeSourceSelector v-model="formState.knowledge_source_ids" />
          <ReadinessChecklist :readiness="aiAgent?.readiness" />
        </div>
        <template v-if="activeTab === 'connections'">
          <div
            class="grid grid-cols-1 items-start gap-8 lg:grid-cols-[minmax(0,640px)_280px]"
          >
            <div class="flex min-w-0 flex-col gap-8">
              <!-- Name Input -->
              <div>
                <Input
                  v-model="formState.name"
                  :label="t('AI_AGENT.NAME.LABEL')"
                  :placeholder="t('AI_AGENT.NAME.PLACEHOLDER')"
                />
              </div>

              <!-- Inbox Selection -->
              <div>
                <h3 class="mb-2 text-sm font-medium text-n-slate-12">
                  {{ t('AI_AGENT.INBOXES.LABEL') }}
                </h3>
                <p class="mb-4 text-sm text-n-slate-11">
                  {{ t('AI_AGENT.INBOXES.HELP') }}
                </p>
                <p v-if="inboxError" class="mb-4 text-sm text-n-ruby-11">
                  {{ inboxError }}
                </p>
                <div
                  v-if="inboxList.length === 0"
                  class="text-sm text-n-slate-11"
                >
                  {{ t('AI_AGENT.INBOXES.NONE') }}
                </div>
                <div v-else class="flex flex-col gap-2">
                  <label
                    v-for="inbox in inboxList"
                    :key="inbox.id"
                    :for="`inbox-${inbox.id}`"
                    class="flex items-center gap-3 p-3 rounded-lg border border-n-weak dark:border-n-weak"
                    :class="[
                      inbox.conflicting
                        ? 'opacity-60 cursor-not-allowed bg-n-alpha-black1'
                        : 'hover:bg-n-alpha-black1 cursor-pointer',
                    ]"
                    @click.prevent="toggleInbox(inbox.id)"
                  >
                    <input
                      :id="`inbox-${inbox.id}`"
                      type="checkbox"
                      :checked="isInboxSelected(inbox.id)"
                      :disabled="inbox.conflicting"
                      :aria-label="inbox.name"
                      class="w-4 h-4 rounded border-n-slate-6 text-n-brand focus:ring-n-brand"
                      @click.stop
                      @change="toggleInbox(inbox.id)"
                    />
                    <Avatar
                      :name="inbox.name"
                      :src="inbox.avatar_url"
                      :size="28"
                      rounded-full
                    />
                    <div class="flex flex-col">
                      <span class="text-sm font-medium text-n-slate-12">
                        {{ inbox.name }}
                      </span>
                      <span class="text-xs text-n-slate-11">
                        {{ getInboxStatusText(inbox) }}
                      </span>
                    </div>
                  </label>
                </div>
              </div>

              <div>
                <h3 class="mb-2 text-sm font-medium text-n-slate-12">
                  {{ t('AI_AGENT.TOOLS.LABEL') }}
                </h3>
                <p class="mb-4 text-sm text-n-slate-11">
                  {{ t('AI_AGENT.TOOLS.HELP') }}
                </p>

                <div class="flex flex-col gap-4">
                  <div
                    v-for="tool in availableTools"
                    :id="`tool-${tool.key}`"
                    :key="tool.key"
                    class="p-4 rounded-lg border border-n-weak dark:border-n-weak"
                  >
                    <div class="flex items-start justify-between gap-4">
                      <div>
                        <p class="text-sm font-medium text-n-slate-12">
                          {{
                            t(`AI_AGENT.TOOLS.${tool.key.toUpperCase()}.LABEL`)
                          }}
                        </p>
                        <p class="text-sm text-n-slate-11">
                          {{
                            t(`AI_AGENT.TOOLS.${tool.key.toUpperCase()}.HELP`)
                          }}
                        </p>
                      </div>
                      <Switch
                        v-if="tool.key !== 'human_handoff'"
                        :data-testid="`tool-toggle-${tool.key}`"
                        :model-value="isToolEnabled(tool.key)"
                        :aria-label="
                          t(`AI_AGENT.TOOLS.${tool.key.toUpperCase()}.LABEL`)
                        "
                        :disabled="
                          tool.key === 'ikas_catalog_search'
                            ? !isIkasAvailable || !isIkasCatalogReady
                            : tool.key === 'ikas_lookup_order' &&
                              !isIkasAvailable
                        "
                        @update:model-value="toggleTool(tool.key)"
                      />
                    </div>

                    <div
                      v-if="tool.key === 'human_handoff'"
                      class="mt-4 flex flex-col gap-4"
                    >
                      <div class="flex flex-col gap-1">
                        <label
                          class="mb-0.5 text-sm font-medium text-n-slate-12"
                        >
                          {{
                            t(
                              'AI_AGENT.TOOLS.HUMAN_HANDOFF.ALLOWED_LABELS_LABEL'
                            )
                          }}
                        </label>
                        <TagMultiSelectComboBox
                          :model-value="
                            formState.tools.human_handoff.allowed_labels
                          "
                          :options="handoffLabelOptions"
                          :placeholder="
                            t(
                              'AI_AGENT.TOOLS.HUMAN_HANDOFF.ALLOWED_LABELS_PLACEHOLDER'
                            )
                          "
                          :search-placeholder="
                            t(
                              'AI_AGENT.TOOLS.HUMAN_HANDOFF.ALLOWED_LABELS_SEARCH_PLACEHOLDER'
                            )
                          "
                          :empty-state="
                            t(
                              'AI_AGENT.TOOLS.HUMAN_HANDOFF.ALLOWED_LABELS_EMPTY'
                            )
                          "
                          @update:model-value="updateHandoffLabels"
                        />
                      </div>

                      <p class="text-xs text-n-slate-10">
                        {{
                          t('AI_AGENT.TOOLS.HUMAN_HANDOFF.ALLOWED_LABELS_HELP')
                        }}
                      </p>
                    </div>

                    <p
                      v-if="tool.key.startsWith('ikas_')"
                      class="mt-3 text-xs"
                      :class="
                        isIkasAvailable ? 'text-n-teal-11' : 'text-n-slate-11'
                      "
                    >
                      <template v-if="tool.key === 'ikas_catalog_search'">
                        {{
                          isIkasAvailable && isIkasCatalogReady
                            ? t('AI_AGENT.TOOLS.IKAS_CATALOG_SEARCH.READY')
                            : t(
                                'AI_AGENT.TOOLS.IKAS_CATALOG_SEARCH.UNAVAILABLE',
                                {
                                  state: ikasIntegration.state,
                                  catalogStatus:
                                    ikasIntegration.catalog_sync?.status ||
                                    'not_synced',
                                }
                              )
                        }}
                      </template>
                      <template v-else>
                        {{
                          isIkasAvailable
                            ? t('AI_AGENT.TOOLS.IKAS_LOOKUP_ORDER.CONNECTED')
                            : t(
                                'AI_AGENT.TOOLS.IKAS_LOOKUP_ORDER.UNAVAILABLE',
                                {
                                  state: ikasIntegration.state,
                                }
                              )
                        }}
                      </template>
                    </p>
                  </div>
                </div>
              </div>
            </div>
            <ReadinessChecklist :readiness="aiAgent?.readiness" />
          </div>
        </template>
        <div
          v-if="activeTab === 'test'"
          class="grid grid-cols-1 items-start gap-8 lg:grid-cols-[minmax(0,1fr)_280px]"
        >
          <!-- Test Conversations -->
          <div>
            <h3 class="mb-2 text-sm font-medium text-n-slate-12">
              {{ t('AI_AGENT.TEST_CONVERSATIONS.TITLE') }}
            </h3>
            <p v-if="isSimulatorDisabled" class="mb-3 text-sm text-n-slate-11">
              {{ simulatorDisabledMessage }}
            </p>
            <TestConversationLayout
              :ai-agent-id="agentId"
              :is-disabled="isSimulatorDisabled"
            />
          </div>
          <ReadinessChecklist :readiness="aiAgent?.readiness" />
        </div>
        <ImproveWorkspace
          v-if="activeTab === 'improve'"
          :ai-agent-id="agentId"
          :mode="improveMode"
          :has-unsaved-instructions="isInstructionsDirty"
          :auto-learning-enabled="Boolean(aiAgent?.auto_learning_enabled)"
          @draft-updated="refreshAfterLearningApplied"
        />
      </div>
    </template>
  </SettingsLayout>
  <AssistantReleaseHistoryDialog
    v-if="aiAgent?.id"
    ref="releaseHistoryRef"
    assistant-type="text"
    :assistant-id="aiAgent.id"
    :current-release-id="aiAgent.current_release?.id"
    @restored="handleReleaseRestored"
  />
</template>
