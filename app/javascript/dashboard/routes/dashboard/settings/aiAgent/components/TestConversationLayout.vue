<script setup>
import { computed, ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import ImprovementCreditsSummary from './ImprovementCreditsSummary.vue';
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

const showListOnMobile = ref(true);
const creditsSummaryRef = ref(null);
const improvementUsage = ref(null);
const creditsExhausted = computed(
  () => improvementUsage.value?.status === 'exhausted'
);

const handleImprovementUsageLoaded = usage => {
  improvementUsage.value = usage;
};

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

const sendMessage = async payload => {
  if (!activeConversation.value || creditsExhausted.value) return;
  const messagePayload =
    typeof payload === 'string' ? { content: payload } : payload;
  const result = await store.dispatch('aiAgentTestConversations/sendMessage', {
    aiAgentId: props.aiAgentId,
    id: activeConversation.value.id,
    ...messagePayload,
  });

  if (result?.error) {
    useAlert(result.error || t('AI_AGENT.TEST_CONVERSATIONS.ERROR'));
    await creditsSummaryRef.value?.refresh?.();
    return;
  }

  await creditsSummaryRef.value?.refresh?.();
  emit('tested');
};

const handleBack = () => {
  showListOnMobile.value = true;
};
</script>

<template>
  <div class="flex min-w-0 flex-col gap-3">
    <ImprovementCreditsSummary
      ref="creditsSummaryRef"
      @loaded="handleImprovementUsageLoaded"
    />
    <div
      class="flex h-[44rem] min-h-[36rem] flex-col overflow-hidden rounded-lg border border-n-weak md:h-[calc(100dvh-15rem)] md:max-h-[64rem] md:flex-row dark:border-n-weak"
    >
      <div
        class="w-full border-b border-n-slate-6 md:w-72 md:border-b-0 md:border-r"
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

      <div
        class="min-w-0 flex-1 flex-col"
        :class="!showListOnMobile ? 'flex' : 'hidden md:flex'"
      >
        <TestConversationChatPanel
          :conversation="activeConversation"
          :ui-flags="uiFlags"
          :is-disabled="isDisabled || creditsExhausted"
          @send="sendMessage"
          @back="handleBack"
        />
      </div>
    </div>
  </div>
</template>
