<script setup>
import { ref, computed, onMounted } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TestConversationLayout from './components/TestConversationLayout.vue';

const store = useStore();
const { t } = useI18n();

const aiAgent = useMapGetter('aiAgent/getAiAgent');
const uiFlags = useMapGetter('aiAgent/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');

const isSaving = ref(false);

// Local form state - initialized from store on load
const formState = ref({
  enabled: false,
  prompt: '',
  inbox_ids: [],
});

const isFormDirty = computed(() => {
  const record = aiAgent.value;
  if (!record) {
    return (
      formState.value.enabled !== false ||
      formState.value.prompt !== '' ||
      formState.value.inbox_ids.length !== 0
    );
  }
  return (
    formState.value.enabled !== record.enabled ||
    formState.value.prompt !== (record.prompt || '') ||
    JSON.stringify(formState.value.inbox_ids) !==
      JSON.stringify(record.inbox_ids || [])
  );
});

const maxCharacters = 4000;

const inboxList = computed(() => {
  return inboxes.value || [];
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

const isSimulatorDisabled = computed(() => {
  return !formState.value.enabled || !formState.value.prompt.trim();
});

const toggleInbox = inboxId => {
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

const handleSave = async () => {
  isSaving.value = true;
  try {
    const payload = {
      enabled: formState.value.enabled,
      prompt: formState.value.prompt,
      inbox_ids: formState.value.inbox_ids,
    };
    const result = await store.dispatch('aiAgent/update', payload);
    if (result) {
      useAlert(t('AI_AGENT.SAVE.SUCCESS'));
    } else {
      useAlert(t('AI_AGENT.SAVE.ERROR'));
    }
  } catch {
    useAlert(t('AI_AGENT.SAVE.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const syncFormState = () => {
  const record = aiAgent.value;
  if (record) {
    formState.value = {
      enabled: record.enabled || false,
      prompt: record.prompt || '',
      inbox_ids: record.inbox_ids || [],
    };
  } else {
    formState.value = {
      enabled: false,
      prompt: '',
      inbox_ids: [],
    };
  }
};

onMounted(async () => {
  await store.dispatch('aiAgent/get');
  await store.dispatch('aiAgentTestConversations/get');
  syncFormState();
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
      />
    </template>
    <template #body>
      <div class="flex flex-col gap-8">
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
            :message="t('AI_AGENT.PROMPT.HELP')"
            message-type="info"
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
          <div v-if="inboxList.length === 0" class="text-sm text-n-slate-11">
            {{ t('AI_AGENT.INBOXES.NONE') }}
          </div>
          <div v-else class="flex flex-col gap-2">
            <div
              v-for="inbox in inboxList"
              :key="inbox.id"
              class="flex items-center gap-3 p-3 rounded-lg border border-n-weak dark:border-n-weak hover:bg-n-alpha-black1 cursor-pointer"
              @click="toggleInbox(inbox.id)"
            >
              <input
                type="checkbox"
                :checked="isInboxSelected(inbox.id)"
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
                  {{ inbox.channel_type }}
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

        <!-- Test Conversations -->
        <div>
          <h3 class="mb-2 text-sm font-medium text-n-slate-12">
            {{ t('AI_AGENT.TEST_CONVERSATIONS.TITLE') }}
          </h3>
          <TestConversationLayout :is-disabled="isSimulatorDisabled" />
        </div>

        <!-- Save Button -->
        <div class="flex justify-end">
          <Button
            :label="t('AI_AGENT.SAVE.BUTTON')"
            :is-loading="isSaving"
            :disabled="!isFormDirty || isSaving"
            @click="handleSave"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
