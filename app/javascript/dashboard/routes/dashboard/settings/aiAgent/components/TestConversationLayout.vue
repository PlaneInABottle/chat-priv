<script setup>
import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import TestConversationList from './TestConversationList.vue';
import TestConversationChatPanel from './TestConversationChatPanel.vue';

const props = defineProps({
  aiAgentId: {
    type: Number,
    required: true,
  },
  isDisabled: {
    type: Boolean,
    default: false,
  },
});

const store = useStore();
const { t } = useI18n();

const conversations = useMapGetter(
  'aiAgentTestConversations/getTestConversations'
);
const activeConversation = useMapGetter(
  'aiAgentTestConversations/getActiveTestConversation'
);
const uiFlags = useMapGetter('aiAgentTestConversations/getUIFlags');

const showListOnMobile = ref(true);

const selectConversation = id => {
  if (props.isDisabled) return;
  showListOnMobile.value = false;
  store.dispatch('aiAgentTestConversations/show', {
    aiAgentId: props.aiAgentId,
    id,
  });
};

const createConversation = async () => {
  if (props.isDisabled) return;
  const data = await store.dispatch('aiAgentTestConversations/create', {
    aiAgentId: props.aiAgentId,
  });
  if (data) {
    showListOnMobile.value = false;
  }
};

const deleteConversation = id => {
  if (props.isDisabled) return;
  store.dispatch('aiAgentTestConversations/delete', {
    aiAgentId: props.aiAgentId,
    id,
  });
};

const clearAllConversations = () => {
  if (props.isDisabled) return;
  store.dispatch('aiAgentTestConversations/clearAll', {
    aiAgentId: props.aiAgentId,
  });
};

const sendMessage = async content => {
  if (!activeConversation.value) return;
  const result = await store.dispatch('aiAgentTestConversations/sendMessage', {
    aiAgentId: props.aiAgentId,
    id: activeConversation.value.id,
    content,
  });

  if (result?.error) {
    useAlert(result.error || t('AI_AGENT.TEST_CONVERSATIONS.ERROR'));
  }
};

const handleBack = () => {
  showListOnMobile.value = true;
};
</script>

<template>
  <div
    class="flex flex-col md:flex-row h-[28rem] border rounded-lg border-n-weak dark:border-n-weak overflow-hidden"
  >
    <!-- Sidebar / List -->
    <div
      class="w-full md:w-72 border-b md:border-b-0 md:border-r border-n-slate-6"
      :class="showListOnMobile ? 'flex' : 'hidden md:flex'"
    >
      <TestConversationList
        :conversations="conversations"
        :active-id="activeConversation?.id"
        :ui-flags="uiFlags"
        :is-disabled="isDisabled"
        @select="selectConversation"
        @create="createConversation"
        @delete="deleteConversation"
        @clear-all="clearAllConversations"
      />
    </div>

    <!-- Chat Panel -->
    <div
      class="flex-1 flex flex-col"
      :class="!showListOnMobile ? 'flex' : 'hidden md:flex'"
    >
      <TestConversationChatPanel
        :conversation="activeConversation"
        :ui-flags="uiFlags"
        :is-disabled="isDisabled"
        @send="sendMessage"
        @back="handleBack"
      />
    </div>
  </div>
</template>
