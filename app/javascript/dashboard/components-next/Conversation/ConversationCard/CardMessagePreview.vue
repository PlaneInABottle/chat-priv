<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const { getPlainText } = useMessageFormatter();

const lastNonActivityMessage = computed(
  () => props.conversation.lastNonActivityMessage || {}
);

const isVoiceCallMessage = computed(
  () => lastNonActivityMessage.value?.content_type === 'voice_call'
);

const voiceCallData = computed(() => {
  const call = lastNonActivityMessage.value?.call || {};
  return {
    status: call.status || '',
    direction:
      call.direction === 'outgoing' || call.direction === 'outbound'
        ? 'outbound'
        : 'inbound',
    endReason: call.end_reason || call.endReason || '',
  };
});

const lastNonActivityMessageContent = computed(() => {
  const { customAttributes = {} } = props.conversation;
  const { email: { subject } = {} } = customAttributes;
  return getPlainText(
    subject ||
      lastNonActivityMessage.value?.content ||
      t('CHAT_LIST.NO_CONTENT')
  );
});

const assignee = computed(() => {
  const { meta: { assignee: agent = {} } = {} } = props.conversation;
  return {
    name: agent.name ?? agent.availableName,
    thumbnail: agent.thumbnail,
    status: agent.availabilityStatus,
  };
});

const unreadMessagesCount = computed(() => {
  const { unreadCount } = props.conversation;
  return unreadCount;
});
const hasVoiceAiHandoff = computed(
  () =>
    props.conversation.additionalAttributes?.voiceAiHandoffStatus ===
      'requested' ||
    props.conversation.additional_attributes?.voice_ai_handoff_status ===
      'requested'
);
</script>

<template>
  <div class="flex w-full flex-col gap-1 pb-1">
    <div class="flex items-end w-full gap-2">
      <div v-if="isVoiceCallMessage" class="w-full mb-0">
        <VoiceCallStatus
          :status="voiceCallData.status"
          :direction="voiceCallData.direction"
          :end-reason="voiceCallData.endReason"
        />
      </div>
      <p
        v-else
        class="w-full mb-0 text-sm leading-7 text-n-slate-12 line-clamp-2"
      >
        {{ lastNonActivityMessageContent }}
      </p>
      <div class="flex items-center flex-shrink-0 gap-2 pb-2">
        <Avatar
          v-if="assignee.name"
          :name="assignee.name"
          :src="assignee.thumbnail"
          :size="20"
          :status="assignee.status"
          rounded-full
        />
        <div
          v-if="unreadMessagesCount > 0"
          class="inline-flex items-center justify-center rounded-full size-5 bg-n-brand"
        >
          <span class="text-xs font-semibold text-white">
            {{ unreadMessagesCount }}
          </span>
        </div>
      </div>
    </div>
    <span
      v-if="hasVoiceAiHandoff"
      class="inline-flex w-fit rounded-full bg-n-amber-3 px-2 py-0.5 text-xs font-medium text-n-amber-11"
    >
      {{ t('CONVERSATION.VOICE_CALL.HANDOFF_REQUESTED') }}
    </span>
  </div>
</template>
