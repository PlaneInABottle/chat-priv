<script setup>
import { onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import TestConversationChatPanel from './TestConversationChatPanel.vue';

const props = defineProps({
  aiAgentId: { type: Number, required: true },
  draftInstructions: { type: Object, required: true },
  isDraft: { type: Boolean, default: false },
  isDisabled: { type: Boolean, default: false },
});

const emit = defineEmits(['tested']);

const store = useStore();
const { t } = useI18n();

const conversations = useMapGetter(
  'aiAgentTestConversations/getTestConversations'
);
const activeConversation = useMapGetter(
  'aiAgentTestConversations/getActiveTestConversation'
);
const uiFlags = useMapGetter('aiAgentTestConversations/getUIFlags');

const selectConversation = id => {
  if (!id) return;
  store.dispatch('aiAgentTestConversations/show', {
    aiAgentId: props.aiAgentId,
    id: Number(id),
  });
};

const createConversation = async () => {
  await store.dispatch('aiAgentTestConversations/create', {
    aiAgentId: props.aiAgentId,
  });
};

const sendMessage = async content => {
  if (!activeConversation.value) return;

  const result = await store.dispatch('aiAgentTestConversations/sendMessage', {
    aiAgentId: props.aiAgentId,
    id: activeConversation.value.id,
    content,
    draftInstructions: props.isDraft ? props.draftInstructions : undefined,
  });

  if (result?.error) {
    useAlert(result.error || t('AI_AGENT.TEST_CONVERSATIONS.ERROR'));
    return;
  }

  emit('tested');
};

const selectLatestConversation = items => {
  if (!activeConversation.value && items.length) {
    selectConversation(items[0].id);
  }
};

watch(conversations, selectLatestConversation);
onMounted(() => selectLatestConversation(conversations.value));
</script>

<template>
  <aside
    class="flex h-[32rem] flex-col overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 md:h-[calc(100dvh-22rem)] md:min-h-[26rem] md:max-h-[48rem]"
    :aria-label="t('AI_ASSISTANT.INSTRUCTIONS.DRAFT_TEST')"
  >
    <div class="flex flex-col gap-3 border-b border-n-weak p-4">
      <div class="flex items-start justify-between gap-3">
        <div>
          <div class="flex flex-wrap items-center gap-2">
            <h2 class="m-0 text-sm font-semibold text-n-slate-12">
              {{ t('AI_ASSISTANT.INSTRUCTIONS.DRAFT_TEST') }}
            </h2>
            <span
              v-if="isDraft"
              class="rounded-md bg-n-amber-3 px-2 py-1 text-xs font-medium text-n-amber-11"
            >
              {{ t('AI_ASSISTANT.INSTRUCTIONS.UNSAVED_DRAFT') }}
            </span>
          </div>
          <p class="mb-0 mt-1 text-xs text-n-slate-10">
            {{ t('AI_ASSISTANT.INSTRUCTIONS.DRAFT_TEST_HELP') }}
          </p>
        </div>
        <Button
          icon="i-lucide-message-square-plus"
          size="sm"
          variant="outline"
          color="slate"
          :aria-label="t('AI_AGENT.TEST_CONVERSATIONS.NEW')"
          :is-loading="uiFlags.isCreating"
          :disabled="isDisabled"
          @click="createConversation"
        />
      </div>

      <label class="flex flex-col gap-1 text-xs font-medium text-n-slate-11">
        {{ t('AI_ASSISTANT.INSTRUCTIONS.TEST_CONVERSATION') }}
        <select
          :value="activeConversation?.id || ''"
          :disabled="isDisabled || !conversations.length"
          class="h-9 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-sm font-normal text-n-slate-12"
          @change="selectConversation($event.target.value)"
        >
          <option value="">
            {{ t('AI_ASSISTANT.INSTRUCTIONS.SELECT_TEST') }}
          </option>
          <option
            v-for="conversation in conversations"
            :key="conversation.id"
            :value="conversation.id"
          >
            {{ conversation.title }}
          </option>
        </select>
      </label>
    </div>

    <div class="min-h-0 flex-1">
      <TestConversationChatPanel
        :conversation="activeConversation"
        :ui-flags="uiFlags"
        :is-disabled="isDisabled"
        @send="sendMessage"
      />
    </div>
  </aside>
</template>
