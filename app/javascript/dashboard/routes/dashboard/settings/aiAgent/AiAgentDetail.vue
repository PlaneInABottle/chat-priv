<script setup>
import { ref, computed, nextTick, onMounted, watch } from 'vue';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TestConversationLayout from './components/TestConversationLayout.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import InstructionWorkspace from './components/InstructionWorkspace.vue';
import AssistantStatusBadge from './components/AssistantStatusBadge.vue';
import ReadinessChecklist from './components/ReadinessChecklist.vue';
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

const store = useStore();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const agentId = computed(() => Number(route.params.id));

const aiAgent = useMapGetter('aiAgent/getAiAgent');
const uiFlags = useMapGetter('aiAgent/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');

const isSaving = ref(false);
const inboxError = ref('');
const activeTab = computed(() => {
  if (route.name === 'ai_agent_test') return 'test';
  if (route.name === 'ai_agent_detail') return 'connections';
  return 'instructions';
});

// Local form state - initialized from store on load
const formState = ref({
  name: '',
  instructions: normalizeInstructionDocument(),
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
  () => isInstructionsDirty.value || isConnectionsDirty.value
);

const tabs = computed(() => [
  { label: t('AI_AGENT.TABS.INSTRUCTIONS'), value: 'instructions' },
  { label: t('AI_AGENT.TABS.CONNECTIONS'), value: 'connections' },
  { label: t('AI_AGENT.TABS.TEST_HISTORY'), value: 'test' },
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

const simulatorDisabledMessage = computed(() => {
  return simulatorDisabledMessageKey.value
    ? t(simulatorDisabledMessageKey.value)
    : '';
});

const isCurrentTabDirty = computed(() =>
  activeTab.value === 'instructions'
    ? isInstructionsDirty.value
    : isConnectionsDirty.value
);

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
      inbox_ids: record.agent_bot?.inbox_ids || [],
      tools: normalizeToolsState(record.tools_config),
    };
  } else {
    formState.value = {
      name: '',
      instructions: normalizeInstructionDocument(),
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

const handleSave = async () => {
  isSaving.value = true;
  inboxError.value = '';
  const instructionsDraft = formState.value.instructions;
  const connectionsDraft = {
    name: formState.value.name,
    inbox_ids: formState.value.inbox_ids,
    tools: formState.value.tools,
  };
  const preserveInstructionsDraft =
    activeTab.value === 'connections' && isInstructionsDirty.value;
  const preserveConnectionsDraft =
    activeTab.value === 'instructions' && isConnectionsDirty.value;

  try {
    const tools = normalizeToolsState(formState.value.tools);
    const config = {
      ...(aiAgent.value?.config || {}),
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
    };

    if (activeTab.value === 'instructions') {
      config.instructions = normalizeInstructionDocument(
        formState.value.instructions
      );
    }

    const payload = {
      id: agentId.value,
      data: {
        name: formState.value.name,
        inbox_ids: formState.value.inbox_ids,
        config,
      },
    };
    const result = await store.dispatch('aiAgent/update', payload);
    if (result?.id) {
      useAlert(t('AI_AGENT.SAVE.SUCCESS'));
      syncFormState();
      if (preserveInstructionsDraft) {
        formState.value.instructions = instructionsDraft;
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

const goBack = () => {
  router.push({ name: 'ai_agents' });
};

onBeforeRouteLeave(to => {
  const detailRoutes = [
    'ai_agent_instructions',
    'ai_agent_detail',
    'ai_agent_test',
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
    connections: 'ai_agent_detail',
    test: 'ai_agent_test',
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
  await store.dispatch('aiAgent/show', agentId.value);
  formState.value.instructions = draft;
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
  const result = await store.dispatch('aiAgent/publish', agentId.value);
  if (result?.id) {
    syncFormState();
    useAlert(t('AI_ASSISTANT.ACTIONS.PUBLISHED'));
  } else {
    useAlert(result?.error || t('AI_ASSISTANT.ACTIONS.PUBLISH_ERROR'));
  }
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
        :title="t('AI_AGENT.HEADER')"
        :description="t('AI_AGENT.DESCRIPTION')"
        :link-text="t('AI_AGENT.LEARN_MORE')"
        feature-name="ai_agent"
      >
        <template #actions>
          <AssistantStatusBadge :status="lifecycleStatus" />
          <Button
            v-if="isActive"
            icon="i-lucide-pause"
            variant="outline"
            color="amber"
            :label="t('AI_ASSISTANT.ACTIONS.PAUSE')"
            @click="handlePause"
          />
          <Button
            v-else
            icon="i-lucide-rocket"
            :label="t('AI_ASSISTANT.ACTIONS.PUBLISH')"
            :disabled="!aiAgent?.readiness?.can_publish || isFormDirty"
            @click="handlePublish"
          />
          <Button
            icon="i-lucide-arrow-left"
            variant="outline"
            color="slate"
            :label="t('AI_AGENT.BACK')"
            @click="goBack"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <div class="flex flex-col gap-6">
        <div
          v-if="isActive"
          class="flex items-start gap-3 rounded-lg border border-n-teal-5 bg-n-teal-2 p-4 text-sm text-n-teal-11"
        >
          <span class="i-lucide-shield-check mt-0.5 size-4 flex-shrink-0" />
          <p class="m-0">{{ t('AI_ASSISTANT.ACTIVE_NOTICE') }}</p>
        </div>
        <div
          class="sticky top-0 z-20 flex flex-col gap-3 border-b border-n-weak bg-n-surface-1 py-3 sm:flex-row sm:items-center sm:justify-between"
        >
          <TabBar
            :tabs="tabs"
            :initial-active-tab="activeTabIndex"
            @tab-changed="handleTabChange"
          />
          <Button
            v-if="activeTab !== 'test'"
            :label="t('AI_AGENT.SAVE.BUTTON')"
            :is-loading="isSaving"
            :disabled="isSaveDisabled"
            @click="handleSave"
          />
        </div>
        <InstructionWorkspace
          v-if="activeTab === 'instructions'"
          v-model="formState.instructions"
          :ai-agent-id="agentId"
          :is-dirty="isInstructionsDirty"
          :is-disabled="!hasInstructionContent(formState.instructions)"
          @configure-handoff="configureHandoff"
          @tested="refreshAfterDraftTest"
        />
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
      </div>
    </template>
  </SettingsLayout>
</template>
