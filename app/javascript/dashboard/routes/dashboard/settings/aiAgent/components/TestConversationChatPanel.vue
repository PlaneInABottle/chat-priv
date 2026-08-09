<script setup>
import { ref, watch, nextTick, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
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
  showBackButton: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['send', 'back']);

const { t } = useI18n();
const { formatMessage } = useMessageFormatter();

const inputValue = ref('');
const messageAreaRef = ref(null);

const isAtLimit = computed(() => {
  return (props.conversation?.messages_count || 0) >= 200;
});

const isInputDisabled = computed(() => {
  return props.isDisabled || props.uiFlags.isSending || isAtLimit.value;
});

const isWaitingForResponse = computed(
  () =>
    props.uiFlags.isSending &&
    props.conversation?.id === props.uiFlags.sendingConversationId
);

const isHandoffPreview = message => message?.terminal_action === 'handoff';
const isOptionsPreview = message =>
  message?.terminal_action === 'present_options' &&
  message?.tool_result?.presentation?.content_type === 'input_select';
const isCatalogProductsPreview = message =>
  message?.terminal_action === 'present_catalog_products' &&
  message?.tool_result?.presentation?.content_type === 'catalog_products';

const catalogPriceText = item => {
  const price = item?.price;
  const hasCurrentAmount =
    price?.amount !== undefined && price?.amount !== null;
  const amount = hasCurrentAmount ? price.amount : price?.reference_amount;
  if (amount === undefined || amount === null || !price?.currency) return '';

  const key =
    price.final_total_known === false || !hasCurrentAmount
      ? 'AI_AGENT.TEST_CONVERSATIONS.REFERENCE_PRICE'
      : 'AI_AGENT.TEST_CONVERSATIONS.PRICE';
  return t(key, { amount, currency: price.currency });
};

const isOptionPromptStale = message => {
  const messages = props.conversation?.messages || [];
  const messageIndex = messages.findIndex(
    candidate => candidate.id === message.id
  );
  if (messageIndex < 0) return true;

  return messages
    .slice(messageIndex + 1)
    .some(candidate => candidate.role === 'user');
};

const handoffPreviewSummary = message => {
  return (
    message?.tool_result?.customer_message ||
    message?.content ||
    t('AI_AGENT.TEST_CONVERSATIONS.HANDOFF_PREVIEW')
  );
};

const formattedAssistantMessages = computed(() =>
  Object.fromEntries(
    (props.conversation?.messages || [])
      .filter(message => message.role === 'assistant')
      .map(message => [
        message.id,
        formatMessage(message.content || '', false, false, true),
      ])
  )
);

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

const handleSend = event => {
  event?.preventDefault?.();
  event?.stopPropagation?.();

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

const handleOptionSelect = (message, option) => {
  if (
    isInputDisabled.value ||
    message.submitted_values?.length ||
    isOptionPromptStale(message)
  )
    return;

  emit('send', {
    content: option.title,
    replyToMessageId: message.id,
    selectedValue: option.value,
  });
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
          v-if="showBackButton"
          data-testid="test-conversation-back"
          type="button"
          class="md:hidden p-1 rounded-md hover:bg-n-alpha-black1"
          :aria-label="t('AI_AGENT.BACK')"
          @click="emit('back')"
        >
          <Icon
            icon="i-lucide-arrow-left"
            class="text-n-slate-11 size-5"
            aria-hidden="true"
          />
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
      <div
        ref="messageAreaRef"
        class="flex-1 overflow-y-auto p-4 space-y-3"
        aria-live="polite"
        :aria-busy="isWaitingForResponse"
      >
        <div
          v-for="msg in conversation.messages"
          :key="msg.id"
          class="flex"
          :class="msg.role === 'user' ? 'justify-end' : 'justify-start'"
        >
          <div
            class="min-w-0 max-w-[80%] break-words px-4 py-2 text-sm"
            :class="
              msg.role === 'user'
                ? 'whitespace-pre-wrap bg-n-brand text-white rounded-2xl rounded-tr-sm'
                : 'bg-n-slate-3 dark:bg-n-slate-8 text-n-slate-12 rounded-2xl rounded-tl-sm'
            "
          >
            <template v-if="isHandoffPreview(msg)">
              <p class="font-medium text-n-amber-11">
                {{ t('AI_AGENT.TEST_CONVERSATIONS.HANDOFF_TITLE') }}
              </p>
              <p>{{ handoffPreviewSummary(msg) }}</p>
              <p
                v-if="msg.tool_result?.private_note_preview"
                class="mt-2 text-xs text-n-slate-11"
              >
                {{ t('AI_AGENT.TEST_CONVERSATIONS.INTERNAL_NOTE') }}
                {{ msg.tool_result.private_note_preview }}
              </p>
              <p
                v-if="msg.tool_result?.labels_to_apply?.length"
                class="mt-1 text-xs text-n-slate-11"
              >
                {{ t('AI_AGENT.TEST_CONVERSATIONS.LABELS_TO_APPLY') }}
                {{ msg.tool_result.labels_to_apply.join(', ') }}
              </p>
              <p
                v-if="msg.tool_result?.labels_ignored?.length"
                class="mt-1 text-xs text-n-slate-10"
              >
                {{ t('AI_AGENT.TEST_CONVERSATIONS.LABELS_IGNORED') }}
                {{ msg.tool_result.labels_ignored.join(', ') }}
              </p>
            </template>
            <template v-else-if="isOptionsPreview(msg)">
              <p class="whitespace-pre-wrap">{{ msg.content }}</p>
              <div class="mt-2 flex flex-col gap-1.5">
                <button
                  v-for="option in msg.tool_result.presentation.items"
                  :key="option.value"
                  type="button"
                  class="rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-left text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-60"
                  :class="{
                    'border-n-brand bg-n-brand/10':
                      msg.submitted_values?.[0]?.value === option.value,
                  }"
                  :disabled="
                    isInputDisabled ||
                    !!msg.submitted_values?.length ||
                    isOptionPromptStale(msg)
                  "
                  @click="handleOptionSelect(msg, option)"
                >
                  {{ option.title }}
                </button>
              </div>
            </template>
            <template v-else-if="isCatalogProductsPreview(msg)">
              <p class="whitespace-pre-wrap">{{ msg.content }}</p>
              <div class="mt-3 grid gap-3 sm:grid-cols-2">
                <article
                  v-for="item in msg.tool_result.presentation.items"
                  :key="item.item_id"
                  class="overflow-hidden rounded-xl border border-n-weak bg-n-background"
                >
                  <img
                    v-for="image in item.images"
                    :key="image"
                    :src="image"
                    :alt="item.display_name"
                    class="aspect-square w-full object-cover"
                  />
                  <div class="space-y-1.5 p-3">
                    <p class="font-medium text-n-slate-12">
                      {{ item.display_name }}
                    </p>
                    <p
                      v-if="catalogPriceText(item)"
                      class="text-xs text-n-slate-11"
                    >
                      {{ catalogPriceText(item) }}
                    </p>
                    <p
                      v-if="
                        item.maximum_dimensions?.width &&
                        item.maximum_dimensions?.height &&
                        item.maximum_dimensions?.unit
                      "
                      class="text-xs text-n-slate-11"
                    >
                      {{
                        t('AI_AGENT.TEST_CONVERSATIONS.MAXIMUM_DIMENSIONS', {
                          width: item.maximum_dimensions.width,
                          height: item.maximum_dimensions.height,
                          unit: item.maximum_dimensions.unit,
                        })
                      }}
                    </p>
                    <a
                      v-if="item.link?.url"
                      :href="item.link.url"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="inline-block text-xs text-n-brand hover:underline"
                    >
                      {{ item.display_name }}
                    </a>
                  </div>
                </article>
              </div>
            </template>
            <template v-else-if="msg.role === 'user'">
              {{ msg.content }}
            </template>
            <div
              v-else
              v-dompurify-html="formattedAssistantMessages[msg.id] || ''"
              data-testid="assistant-message-content"
              class="prose prose-sm prose-bubble max-w-none break-words dark:prose-invert"
            />
            <div
              v-if="msg.role === 'assistant' && msg.source_attributions?.length"
              class="flex flex-wrap items-center gap-1.5 mt-2 pt-2 border-t border-n-weak"
            >
              <Icon
                icon="i-lucide-book-open"
                class="size-3.5 text-n-slate-10"
              />
              <span class="text-xs text-n-slate-10">
                {{ t('AI_AGENT.TEST_CONVERSATIONS.SOURCES_USED') }}
              </span>
              <span
                v-for="source in msg.source_attributions"
                :key="`${source.source_id}-${source.source_name}`"
                class="max-w-full px-1.5 py-0.5 text-xs truncate rounded bg-n-alpha-black2 text-n-slate-11"
                :title="source.source_name"
              >
                {{ source.source_name }}
              </span>
            </div>
          </div>
        </div>

        <!-- Loading indicator -->
        <div v-if="isWaitingForResponse" class="flex justify-start">
          <div
            data-testid="response-waiting-indicator"
            class="bg-n-slate-3 dark:bg-n-slate-8 text-n-slate-12 rounded-2xl rounded-tl-sm px-4 py-2 max-w-[80%] text-sm"
          >
            <span class="mr-1">
              {{ t('AI_AGENT.TEST_CONVERSATIONS.RESPONSE_WAIT') }}
            </span>
            <span class="typing-indicator" aria-hidden="true">
              <span />
              <span />
              <span />
            </span>
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
          name="test-message"
          autocomplete="off"
          :placeholder="t('AI_AGENT.TEST_CONVERSATIONS.PLACEHOLDER')"
          :disabled="isInputDisabled"
          class="flex-1 px-3 py-2 text-sm border rounded-lg bg-n-alpha-black2 border-n-weak dark:border-n-weak text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-1 focus:ring-n-brand disabled:opacity-50 disabled:cursor-not-allowed"
          @keyup="handleKeyup"
        />
        <Button
          icon="i-lucide-send"
          type="button"
          :aria-label="t('AI_AGENT.TEST_CONVERSATIONS.SEND')"
          :disabled="isInputDisabled || !inputValue.trim()"
          size="sm"
          @click.stop.prevent="handleSend"
        />
      </div>
    </template>
  </div>
</template>

<style scoped>
.typing-indicator {
  display: inline-flex;
  align-items: center;
  gap: 3px;
}

.typing-indicator span {
  width: 4px;
  height: 4px;
  border-radius: 9999px;
  background-color: currentColor;
  opacity: 0.3;
  animation: typing-bounce 1.2s ease-in-out infinite;
}

.typing-indicator span:nth-child(2) {
  animation-delay: 0.15s;
}

.typing-indicator span:nth-child(3) {
  animation-delay: 0.3s;
}

@keyframes typing-bounce {
  0%,
  60%,
  100% {
    opacity: 0.3;
    transform: translateY(0);
  }

  30% {
    opacity: 1;
    transform: translateY(-2px);
  }
}
</style>
