<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
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
});

const emit = defineEmits(['select', 'create', 'delete', 'clearAll']);

const { t } = useI18n();

const hasConversations = computed(() => props.conversations.length > 0);

const handleClearAll = () => {
  if (window.confirm(t('AI_AGENT.TEST_CONVERSATIONS.CLEAR_ALL_CONFIRM'))) {
    emit('clearAll');
  }
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
          size="small"
          variant="faded"
          :is-loading="uiFlags.isCreating"
          @click="emit('create')"
        />
        <Button
          v-if="hasConversations"
          icon="i-lucide-trash"
          size="small"
          variant="faded"
          color="ruby"
          :is-loading="uiFlags.isDeleting"
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
</template>
