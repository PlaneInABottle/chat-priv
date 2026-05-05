<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDistanceToNow } from 'date-fns';
import Icon from 'dashboard/components-next/icon/Icon.vue';

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

const relativeTime = computed(() => {
  const timestamp = props.conversation.last_message_at;
  if (!timestamp) return '';
  return formatDistanceToNow(new Date(timestamp), { addSuffix: true });
});

const handleDelete = event => {
  event.stopPropagation();
  if (window.confirm(t('AI_AGENT.TEST_CONVERSATIONS.DELETE_CONFIRM'))) {
    emit('delete', props.conversation.id);
  }
};
</script>

<template>
  <div
    class="flex flex-col p-3 rounded-lg cursor-pointer hover:bg-n-alpha-black1 group relative"
    :class="{
      'bg-n-alpha-black1 border-l-2 border-n-brand': isActive,
    }"
    @click="emit('select', conversation.id)"
  >
    <div class="flex items-center justify-between gap-2">
      <span class="text-sm font-medium text-n-slate-12 truncate flex-1">
        {{ conversation.title }}
      </span>
      <button
        class="opacity-0 group-hover:opacity-100 p-1 rounded-md hover:bg-n-alpha-black2 transition-opacity"
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
</template>
