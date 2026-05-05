<script setup>
import { ref, watch, nextTick, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TestConversationEmptyState from './TestConversationEmptyState.vue';

const props = defineProps({
  conversation: {
    type: Object,
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

const emit = defineEmits(['send', 'back']);

const { t } = useI18n();

const inputValue = ref('');
const messageAreaRef = ref(null);

const isAtLimit = computed(() => {
  return (props.conversation?.messages_count || 0) >= 200;
});

const isInputDisabled = computed(() => {
  return props.isDisabled || props.uiFlags.isSending || isAtLimit.value;
});

const scrollToBottom = () => {
  nextTick(() => {
    if (messageAreaRef.value) {
      messageAreaRef.value.scrollTop = messageAreaRef.value.scrollHeight;
    }
  });
};

watch(
  () => props.conversation?.messages?.length,
  () => {
    scrollToBottom();
  }
);

const handleSend = () => {
  const content = inputValue.value.trim();
  if (!content || isInputDisabled.value) return;
  inputValue.value = '';
  emit('send', content);
};

const handleKeyup = event => {
  if (event.key === 'Enter') {
    handleSend();
  }
};
</script>

<template>
  <div class="flex flex-col h-full w-full">
    <!-- Empty state when no conversation selected -->
    <TestConversationEmptyState
      v-if="!conversation"
      type="chat"
      class="h-full"
    />

    <template v-else>
      <!-- Header -->
      <div
        class="flex items-center gap-3 p-3 border-b border-n-slate-6 shrink-0"
      >
        <button
          class="md:hidden p-1 rounded-md hover:bg-n-alpha-black1"
          @click="emit('back')"
        >
          <Icon icon="i-lucide-arrow-left" class="text-n-slate-11 size-5" />
        </button>
        <span
          class="px-2 py-0.5 text-[10px] font-bold tracking-wider uppercase rounded-full bg-n-amber-3 text-n-amber-11 border border-n-amber-6"
        >
          {{ t('AI_AGENT.TEST_CONVERSATIONS.TEST_MODE') }}
        </span>
        <span class="text-sm font-medium text-n-slate-12 truncate">
          {{ conversation.title }}
        </span>
      </div>

      <!-- Message limit warning -->
      <div
        v-if="isAtLimit"
        class="px-4 py-2 text-xs text-center text-n-ruby-11 bg-n-ruby-3 border-b border-n-ruby-6 shrink-0"
      >
        {{ t('AI_AGENT.TEST_CONVERSATIONS.MESSAGE_LIMIT_REACHED') }}
      </div>

      <!-- Messages Area -->
      <div ref="messageAreaRef" class="flex-1 overflow-y-auto p-4 space-y-3">
        <div
          v-for="msg in conversation.messages"
          :key="msg.id"
          class="flex"
          :class="msg.role === 'user' ? 'justify-end' : 'justify-start'"
        >
          <div
            class="text-sm px-4 py-2 max-w-[80%]"
            :class="
              msg.role === 'user'
                ? 'bg-n-brand text-white rounded-2xl rounded-tr-sm'
                : 'bg-n-slate-3 dark:bg-n-slate-8 text-n-slate-12 rounded-2xl rounded-tl-sm'
            "
          >
            {{ msg.content }}
          </div>
        </div>

        <!-- Loading indicator -->
        <div v-if="uiFlags.isSending" class="flex justify-start">
          <div
            class="bg-n-slate-3 dark:bg-n-slate-8 text-n-slate-12 rounded-2xl rounded-tl-sm px-4 py-2 max-w-[80%] text-sm"
          >
            {{ t('AI_AGENT.TEST_CONVERSATIONS.RESPONSE_WAIT') }}
          </div>
        </div>
      </div>

      <!-- Input Area -->
      <div
        class="flex items-center gap-2 p-3 border-t border-n-slate-6 bg-n-alpha-black2 shrink-0"
      >
        <input
          v-model="inputValue"
          type="text"
          :placeholder="t('AI_AGENT.TEST_CONVERSATIONS.PLACEHOLDER')"
          :disabled="isInputDisabled"
          class="flex-1 px-3 py-2 text-sm border rounded-lg bg-n-alpha-black2 border-n-weak dark:border-n-weak text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-1 focus:ring-n-brand disabled:opacity-50 disabled:cursor-not-allowed"
          @keyup="handleKeyup"
        />
        <Button
          icon="i-lucide-send"
          :disabled="isInputDisabled || !inputValue.trim()"
          size="small"
          @click="handleSend"
        />
      </div>
    </template>
  </div>
</template>
