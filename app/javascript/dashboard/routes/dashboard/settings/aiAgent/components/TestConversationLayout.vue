<script setup>
import { ref } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import TestConversationList from './TestConversationList.vue';
import TestConversationChatPanel from './TestConversationChatPanel.vue';

defineProps({
  isDisabled: {
    type: Boolean,
    default: false,
  },
});

const store = useStore();

const conversations = useMapGetter(
  'aiAgentTestConversations/getTestConversations'
);
const activeConversation = useMapGetter(
  'aiAgentTestConversations/getActiveTestConversation'
);
const uiFlags = useMapGetter('aiAgentTestConversations/getUIFlags');

const showListOnMobile = ref(true);

const selectConversation = id => {
  showListOnMobile.value = false;
  store.dispatch('aiAgentTestConversations/show', id);
};

const createConversation = async () => {
  const data = await store.dispatch('aiAgentTestConversations/create');
  if (data) {
    showListOnMobile.value = false;
  }
};

const deleteConversation = id => {
  store.dispatch('aiAgentTestConversations/delete', id);
};

const clearAllConversations = () => {
  store.dispatch('aiAgentTestConversations/clearAll');
};

const sendMessage = content => {
  if (!activeConversation.value) return;
  store.dispatch('aiAgentTestConversations/sendMessage', {
    id: activeConversation.value.id,
    content,
  });
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
