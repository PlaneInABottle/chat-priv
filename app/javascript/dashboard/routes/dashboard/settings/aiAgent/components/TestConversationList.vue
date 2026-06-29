<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TestConversationListItem from './TestConversationListItem.vue';
import TestConversationEmptyState from './TestConversationEmptyState.vue';

const props = defineProps({
  conversations: {
    type: Array,
    default: () => [],
  },
  activeId: {
    type: Number,
    default: null,
  },
  uiFlags: {
    type: Object,
    default: () => ({}),
  },
  isDisabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select', 'create', 'delete', 'clearAll']);

const { t } = useI18n();

const clearAllDialogRef = ref(null);

const hasConversations = computed(() => props.conversations.length > 0);

const handleClearAll = () => {
  clearAllDialogRef.value?.open();
};

const confirmClearAll = () => {
  emit('clearAll');
  clearAllDialogRef.value?.close();
};
</script>

<template>
  <div class="flex flex-col h-full w-full">
    <!-- Header -->
    <div
      class="flex items-center justify-between p-3 border-b border-n-slate-6"
    >
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{ t('AI_AGENT.TEST_CONVERSATIONS.TITLE') }}
      </h3>
      <div class="flex items-center gap-2">
        <Button
          :label="t('AI_AGENT.TEST_CONVERSATIONS.NEW')"
          size="sm"
          variant="faded"
          :is-loading="uiFlags.isCreating"
          :disabled="isDisabled"
          @click="emit('create')"
        />
        <Button
          v-if="hasConversations"
          icon="i-lucide-trash"
          size="sm"
          variant="faded"
          color="ruby"
          :is-loading="uiFlags.isClearing"
          :disabled="isDisabled || uiFlags.isClearing"
          @click="handleClearAll"
        />
      </div>
    </div>

    <!-- List -->
    <div class="flex-1 overflow-y-auto p-2 space-y-1">
      <template v-if="hasConversations">
        <TestConversationListItem
          v-for="conversation in conversations"
          :key="conversation.id"
          :conversation="conversation"
          :is-active="conversation.id === activeId"
          @select="emit('select', $event)"
          @delete="emit('delete', $event)"
        />
      </template>
      <TestConversationEmptyState v-else type="list" />
    </div>
  </div>

  <Dialog
    ref="clearAllDialogRef"
    type="alert"
    :title="t('AI_AGENT.TEST_CONVERSATIONS.CLEAR_ALL_CONFIRM')"
    :confirm-button-label="t('AI_AGENT.TEST_CONVERSATIONS.DELETE')"
    :cancel-button-label="t('AI_AGENT.TEST_CONVERSATIONS.CANCEL')"
    @confirm="confirmClearAll"
  />
</template>
