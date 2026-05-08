<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TestConversationLayout from './components/TestConversationLayout.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import AiAgentToolLogs from './components/AiAgentToolLogs.vue';

const defaultToolsState = () => ({
  enabled: [],
  human_handoff: {
    allowed_labels: [],
  },
  ikas_lookup_order: {
    enabled: false,
  },
});

const normalizeToolsState = toolsConfig => {
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
const activeTab = ref('settings');

// Local form state - initialized from store on load
const formState = ref({
  name: '',
  enabled: false,
  prompt: '',
  inbox_ids: [],
  tools: defaultToolsState(),
});

const isFormDirty = computed(() => {
  const record = aiAgent.value;
  if (!record) {
    return (
      formState.value.name !== '' ||
      formState.value.enabled !== false ||
      formState.value.prompt !== '' ||
      formState.value.inbox_ids.length !== 0 ||
      JSON.stringify(formState.value.tools) !== JSON.stringify(defaultToolsState())
    );
  }
  return (
    formState.value.name !== (record.name || '') ||
    formState.value.enabled !== record.enabled ||
    formState.value.prompt !== (record.prompt || '') ||
    JSON.stringify(formState.value.inbox_ids) !==
      JSON.stringify(record.agent_bot?.inbox_ids || []) ||
    JSON.stringify(formState.value.tools) !==
      JSON.stringify(normalizeToolsState(record.tools_config))
  );
});

const maxCharacters = 4000;

const tabs = computed(() => [
  { label: t('AI_AGENT.TABS.SETTINGS'), value: 'settings' },
  { label: t('AI_AGENT.TABS.TEST'), value: 'test' },
  { label: t('AI_AGENT.TABS.TOOL_LOGS'), value: 'tool_logs' },
]);

const activeTabIndex = computed(() => tabs.value.findIndex(tab => tab.value === activeTab.value));

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

const usageUsed = computed(() => {
  return aiAgent.value?.conversation_count || 0;
});

const usageLimit = computed(() => {
  return aiAgent.value?.conversation_limit || null;
});

const usageDisplay = computed(() => {
  if (usageLimit.value) {
    return t('AI_AGENT.USAGE.COUNT', {
      used: usageUsed.value,
      limit: usageLimit.value,
    });
  }
  return t('AI_AGENT.USAGE.UNLIMITED', { used: usageUsed.value });
});

const hasPersistedPrompt = computed(() => {
  return Boolean(aiAgent.value?.prompt?.trim());
});

const isPersistedEnabled = computed(() => {
  return Boolean(aiAgent.value?.enabled);
});

const hasRecoverablePersistedState = computed(() => {
  return isPersistedEnabled.value && !hasPersistedPrompt.value;
});

const simulatorDisabledMessageKey = computed(() => {
  if (isFormDirty.value) {
    return 'AI_AGENT.TEST_CONVERSATIONS.SAVE_BEFORE_TESTING';
  }

  if (!isPersistedEnabled.value) {
    return 'AI_AGENT.TEST_CONVERSATIONS.ENABLE_BEFORE_TESTING';
  }

  if (!hasPersistedPrompt.value) {
    return 'AI_AGENT.TEST_CONVERSATIONS.ADD_PROMPT_BEFORE_TESTING';
  }

  return null;
});

const promptMessageKey = computed(() => {
  if (formState.value.enabled && !formState.value.prompt.trim()) {
    return 'AI_AGENT.PROMPT.REQUIRED_FOR_TESTING';
  }

  return 'AI_AGENT.PROMPT.HELP';
});

const promptMessageType = computed(() => {
  if (formState.value.enabled && !formState.value.prompt.trim()) {
    return 'warning';
  }

  return 'info';
});

const promptMessage = computed(() => {
  return t(promptMessageKey.value);
});

const isSimulatorDisabled = computed(() => {
  return Boolean(simulatorDisabledMessageKey.value);
});

const simulatorDisabledMessage = computed(() => {
  return simulatorDisabledMessageKey.value
    ? t(simulatorDisabledMessageKey.value)
    : '';
});

const isSaveDisabled = computed(() => {
  return (
    isSaving.value ||
    (!isFormDirty.value && !hasRecoverablePersistedState.value)
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

function syncFormState() {
  const record = aiAgent.value;
  if (record) {
    formState.value = {
      name: record.name || '',
      enabled: record.enabled || false,
      prompt: record.prompt || '',
      inbox_ids: record.agent_bot?.inbox_ids || [],
      tools: normalizeToolsState(record.tools_config),
    };
  } else {
    formState.value = {
      name: '',
      enabled: false,
      prompt: '',
      inbox_ids: [],
      tools: defaultToolsState(),
    };
  }
}

const isToolEnabled = toolKey => formState.value.tools.enabled.includes(toolKey);

const toggleTool = toolKey => {
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
        enabled: toolKey === 'ikas_lookup_order' ? enabled.has(toolKey) : formState.value.tools.ikas_lookup_order.enabled,
      },
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
  try {
    const payload = {
      id: agentId.value,
      data: {
        name: formState.value.name,
        enabled: formState.value.enabled,
        prompt: formState.value.prompt,
        inbox_ids: formState.value.inbox_ids,
        config: {
          ...(aiAgent.value?.config || {}),
          tools: {
            enabled: formState.value.tools.enabled,
            human_handoff: {
              allowed_labels: formState.value.tools.human_handoff.allowed_labels,
            },
            ikas_lookup_order: {
              enabled: formState.value.tools.enabled.includes('ikas_lookup_order'),
            },
          },
        },
      },
    };
    const result = await store.dispatch('aiAgent/update', payload);
    if (result?.id) {
      useAlert(t('AI_AGENT.SAVE.SUCCESS'));
      syncFormState();
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

const handleTabChange = tab => {
  activeTab.value = tab.value;
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
          <Button
            icon="i-lucide-arrow-left"
            variant="faded"
            color="slate"
            :label="t('AI_AGENT.BACK')"
            @click="goBack"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <div class="flex flex-col gap-8">
        <TabBar
          :tabs="tabs"
          :initial-active-tab="activeTabIndex"
          @tab-changed="handleTabChange"
        />
        <template v-if="activeTab === 'settings'">
        <!-- Name Input -->
        <div>
          <woot-input
            v-model="formState.name"
            :label="t('AI_AGENT.NAME.LABEL')"
            :placeholder="t('AI_AGENT.NAME.PLACEHOLDER')"
          />
        </div>

        <!-- Enable/Disable Toggle -->
        <div class="flex items-center justify-between">
          <div class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('AI_AGENT.ENABLED.LABEL') }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ t('AI_AGENT.ENABLED.HELP') }}
            </span>
          </div>
          <Switch v-model="formState.enabled" />
        </div>

        <!-- Prompt Editor -->
        <div>
          <TextArea
            v-model="formState.prompt"
            :label="t('AI_AGENT.PROMPT.LABEL')"
            :placeholder="t('AI_AGENT.PROMPT.PLACEHOLDER')"
            :message="promptMessage"
            :message-type="promptMessageType"
            :max-length="maxCharacters"
            show-character-count
            auto-height
            min-height="8rem"
            max-height="20rem"
            resize
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
          <div v-if="inboxList.length === 0" class="text-sm text-n-slate-11">
            {{ t('AI_AGENT.INBOXES.NONE') }}
          </div>
          <div v-else class="flex flex-col gap-2">
            <div
              v-for="inbox in inboxList"
              :key="inbox.id"
              class="flex items-center gap-3 p-3 rounded-lg border border-n-weak dark:border-n-weak"
              :class="[
                inbox.conflicting
                  ? 'opacity-60 cursor-not-allowed bg-n-alpha-black1'
                  : 'hover:bg-n-alpha-black1 cursor-pointer',
              ]"
              @click="toggleInbox(inbox.id)"
            >
              <input
                type="checkbox"
                :checked="isInboxSelected(inbox.id)"
                :disabled="inbox.conflicting"
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
            </div>
          </div>
        </div>

        <!-- Model Display -->
        <div>
          <h3 class="mb-2 text-sm font-medium text-n-slate-12">
            {{ t('AI_AGENT.MODEL.LABEL') }}
          </h3>
          <div
            class="flex items-center gap-3 p-4 rounded-lg border border-n-weak dark:border-n-weak bg-n-alpha-black1"
          >
            <div
              class="flex items-center justify-center w-10 h-10 rounded-full bg-n-purple-3"
            >
              <Icon icon="i-lucide-brain" class="text-n-purple-9 size-5" />
            </div>
            <div class="flex flex-col">
              <span class="text-sm font-semibold text-n-slate-12">
                {{ aiAgent?.model || '—' }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ t('AI_AGENT.MODEL.HELP') }}
              </span>
            </div>
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
              :key="tool.key"
              class="p-4 rounded-lg border border-n-weak dark:border-n-weak"
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <p class="text-sm font-medium text-n-slate-12">
                    {{ t(`AI_AGENT.TOOLS.${tool.key.toUpperCase()}.LABEL`) }}
                  </p>
                  <p class="text-sm text-n-slate-11">
                    {{ t(`AI_AGENT.TOOLS.${tool.key.toUpperCase()}.HELP`) }}
                  </p>
                </div>
                <Switch
                  :model-value="isToolEnabled(tool.key)"
                  :disabled="tool.key === 'ikas_lookup_order' && !isIkasAvailable"
                  @update:model-value="toggleTool(tool.key)"
                />
              </div>

              <div v-if="tool.key === 'human_handoff'" class="mt-4 flex flex-col gap-4">
                <div class="flex flex-col gap-1">
                  <label class="mb-0.5 text-sm font-medium text-n-slate-12">
                    {{ t('AI_AGENT.TOOLS.HUMAN_HANDOFF.ALLOWED_LABELS_LABEL') }}
                  </label>
                  <TagMultiSelectComboBox
                    :model-value="formState.tools.human_handoff.allowed_labels"
                    :options="handoffLabelOptions"
                    :placeholder="t('AI_AGENT.TOOLS.HUMAN_HANDOFF.ALLOWED_LABELS_PLACEHOLDER')"
                    :search-placeholder="t('AI_AGENT.TOOLS.HUMAN_HANDOFF.ALLOWED_LABELS_SEARCH_PLACEHOLDER')"
                    :empty-state="t('AI_AGENT.TOOLS.HUMAN_HANDOFF.ALLOWED_LABELS_EMPTY')"
                    @update:model-value="updateHandoffLabels"
                  />
                </div>

                <p class="text-xs text-n-slate-10">
                  {{ t('AI_AGENT.TOOLS.HUMAN_HANDOFF.ALLOWED_LABELS_HELP') }}
                </p>
              </div>

              <p
                v-if="tool.key === 'ikas_lookup_order'"
                class="mt-3 text-xs"
                :class="isIkasAvailable ? 'text-n-teal-11' : 'text-n-slate-11'"
              >
                {{
                  isIkasAvailable
                    ? t('AI_AGENT.TOOLS.IKAS_LOOKUP_ORDER.CONNECTED')
                    : t('AI_AGENT.TOOLS.IKAS_LOOKUP_ORDER.UNAVAILABLE', {
                        state: ikasIntegration.state,
                      })
                }}
              </p>
            </div>
          </div>
        </div>

        <!-- Usage Counter -->
        <div>
          <h3 class="mb-2 text-sm font-medium text-n-slate-12">
            {{ t('AI_AGENT.USAGE.LABEL') }}
          </h3>
          <div
            class="flex items-center gap-3 p-4 rounded-lg border border-n-weak dark:border-n-weak bg-n-alpha-black1"
          >
            <div
              class="flex items-center justify-center w-10 h-10 rounded-full bg-n-blue-3"
            >
              <Icon
                icon="i-lucide-message-square"
                class="text-n-brand size-5"
              />
            </div>
            <div class="flex flex-col">
              <span class="text-lg font-semibold text-n-slate-12">
                {{ usageDisplay }}
              </span>
            </div>
          </div>
        </div>
        </template>
        <div v-show="activeTab === 'test'">
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
        </div>
        <template v-if="activeTab === 'tool_logs'">
          <AiAgentToolLogs :ai-agent-id="agentId" />
        </template>

        <!-- Save Button -->
        <div class="flex justify-end">
          <Button
            :label="t('AI_AGENT.SAVE.BUTTON')"
            :is-loading="isSaving"
            :disabled="isSaveDisabled"
            @click="handleSave"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
