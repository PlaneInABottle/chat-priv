<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDistanceToNow } from 'date-fns';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  isActive: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select', 'delete']);

const { t } = useI18n();

const deleteDialogRef = ref(null);

const relativeTime = computed(() => {
  const timestamp = props.conversation.last_message_at;
  if (!timestamp) return '';
  return formatDistanceToNow(new Date(timestamp), { addSuffix: true });
});

const handleDelete = event => {
  event.stopPropagation();
  deleteDialogRef.value?.open();
};

const confirmDelete = () => {
  emit('delete', props.conversation.id);
  deleteDialogRef.value?.close();
};
</script>

<template>
  <div
    class="flex flex-col p-3 rounded-lg cursor-pointer hover:bg-n-alpha-black1 group relative"
    role="button"
    tabindex="0"
    :class="{
      'bg-n-alpha-black1 border-l-2 border-n-brand': isActive,
    }"
    @click="emit('select', conversation.id)"
    @keydown.enter="emit('select', conversation.id)"
    @keydown.space.prevent="emit('select', conversation.id)"
  >
    <div class="flex items-center justify-between gap-2">
      <span class="text-sm font-medium text-n-slate-12 truncate flex-1">
        {{ conversation.title }}
      </span>
      <button
        class="p-1 rounded-md hover:bg-n-alpha-black2 transition-opacity text-n-slate-10 hover:text-n-ruby-11"
        :aria-label="t('AI_AGENT.TEST_CONVERSATIONS.DELETE')"
        @click="handleDelete"
      >
        <Icon icon="i-lucide-trash-2" class="text-n-slate-11 size-3.5" />
      </button>
    </div>
    <p
      v-if="conversation.last_message_preview"
      class="text-xs text-n-slate-11 truncate mt-0.5"
    >
      {{ conversation.last_message_preview }}
    </p>
    <div class="flex items-center gap-2 mt-1">
      <span class="text-xs text-n-slate-10">
        {{
          t('AI_AGENT.TEST_CONVERSATIONS.MESSAGES_COUNT', {
            count: conversation.messages_count || 0,
          })
        }}
      </span>
      <span v-if="relativeTime" class="text-xs text-n-slate-10">
        · {{ relativeTime }}
      </span>
    </div>
  </div>

  <Dialog
    ref="deleteDialogRef"
    type="alert"
    :title="t('AI_AGENT.TEST_CONVERSATIONS.DELETE_CONFIRM')"
    :description="conversation.title"
    :confirm-button-label="t('AI_AGENT.TEST_CONVERSATIONS.DELETE')"
    :cancel-button-label="t('AI_AGENT.TEST_CONVERSATIONS.CANCEL')"
    @confirm="confirmDelete"
  />
</template>
