<script setup>
import VoiceToolEventSummary from './VoiceToolEventSummary.vue';

defineProps({
  event: {
    type: Object,
    required: true,
  },
  voiceAgentName: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <li
    class="mb-2 flex w-full list-none justify-center"
    data-testid="voice-tool-event-segment"
  >
    <VoiceToolEventSummary :event="event" :voice-agent-name="voiceAgentName" />
  </li>
</template>
