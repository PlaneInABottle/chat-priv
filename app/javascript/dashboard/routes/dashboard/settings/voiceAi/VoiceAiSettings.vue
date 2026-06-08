<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { Room, RoomEvent, createLocalAudioTrack } from 'livekit-client';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import VoiceAPI from 'dashboard/api/voice';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const DEFAULT_GREETING = 'Merhaba, size nasil yardimci olabilirim?';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const settings = ref([]);
const selectedInboxId = ref('');
const selectedAiAgentId = ref('');
const selectedFallbackTeamId = ref('');
const greeting = ref(DEFAULT_GREETING);
const instructions = ref('');
const callerName = ref('Test caller');
const callerNumber = ref('+900000000000');
const currentCall = ref(null);
const sessionStatus = ref('disconnected');
const sessionError = ref('');
const activeParticipantType = ref('');
const isLoading = ref(false);
const isSaving = ref(false);
const isCreatingCall = ref(false);
const isJoining = ref(false);
const isEnding = ref(false);
const isTakingOver = ref(false);
const isRefreshing = ref(false);
const isMuted = ref(false);

const roomRef = ref(null);
const localAudioTrackRef = ref(null);
const remoteAudioRef = ref(null);

const inboxes = useMapGetter('inboxes/getInboxes');
const aiAgents = useMapGetter('aiAgent/getAiAgents');
const teams = useMapGetter('teams/getTeams');

const apiInboxes = computed(() =>
  (inboxes.value || []).filter(inbox => inbox.channel_type === INBOX_TYPES.API)
);

const selectedSetting = computed(() =>
  settings.value.find(
    setting => Number(setting.inbox_id) === Number(selectedInboxId.value)
  )
);

const canSave = computed(() => Boolean(selectedInboxId.value));
const canStartTest = computed(
  () => Boolean(selectedInboxId.value) && !isCreatingCall.value
);
const canJoin = computed(
  () => Boolean(currentCall.value?.id) && !isJoining.value
);
const isConnected = computed(() => sessionStatus.value === 'connected');
const hasCall = computed(() => Boolean(currentCall.value?.id));
const sessionStatusLabels = computed(() => ({
  disconnected: t('VOICE_AI.SESSION.DISCONNECTED'),
  connecting: t('VOICE_AI.SESSION.CONNECTING'),
  connected: t('VOICE_AI.SESSION.CONNECTED'),
  failed: t('VOICE_AI.SESSION.FAILED'),
}));

const conversationRoute = computed(() => {
  if (!currentCall.value?.conversation_id) return null;
  return {
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: currentCall.value.conversation_id,
    },
  };
});

const transcriptSegments = computed(
  () => currentCall.value?.transcript_segments || []
);

const sessionStatusLabel = computed(() => {
  return sessionStatusLabels.value[sessionStatus.value] || sessionStatus.value;
});

const settingPayload = () => ({
  inbox_id: selectedInboxId.value,
  ai_agent_id: selectedAiAgentId.value || null,
  fallback_team_id: selectedFallbackTeamId.value || null,
  greeting: greeting.value,
  instructions: instructions.value,
  status: 'test_only',
});

const loadData = async () => {
  isLoading.value = true;
  try {
    await Promise.all([
      store.dispatch('inboxes/get'),
      store.dispatch('aiAgent/get'),
      store.dispatch('teams/get'),
    ]);
    const response = await VoiceAPI.getSettings();
    settings.value = response.data?.payload || [];
    if (!selectedInboxId.value && apiInboxes.value.length) {
      selectedInboxId.value = apiInboxes.value[0].id;
    }
  } finally {
    isLoading.value = false;
  }
};

const syncFormFromSetting = setting => {
  if (!setting) {
    selectedAiAgentId.value = aiAgents.value[0]?.id || '';
    selectedFallbackTeamId.value = '';
    greeting.value = DEFAULT_GREETING;
    instructions.value = '';
    return;
  }

  selectedAiAgentId.value = setting.ai_agent_id || '';
  selectedFallbackTeamId.value = setting.fallback_team_id || '';
  greeting.value = setting.greeting || DEFAULT_GREETING;
  instructions.value = setting.instructions || '';
};

const saveSettings = async ({ silent = false } = {}) => {
  if (!canSave.value) return null;

  isSaving.value = true;
  try {
    const existing = selectedSetting.value;
    const response = existing
      ? await VoiceAPI.updateSetting(existing.id, settingPayload())
      : await VoiceAPI.createSetting(settingPayload());

    const saved = response.data;
    settings.value = [
      ...settings.value.filter(setting => setting.id !== saved.id),
      saved,
    ];
    if (!silent) useAlert(t('VOICE_AI.SETUP.SAVE_SUCCESS'));
    return saved;
  } catch (error) {
    if (!silent) useAlert(t('VOICE_AI.SETUP.SAVE_ERROR'));
    throw error;
  } finally {
    isSaving.value = false;
  }
};

const createTestCall = async () => {
  if (!canStartTest.value) return;

  isCreatingCall.value = true;
  try {
    await saveSettings({ silent: true });
    const response = await VoiceAPI.createTestCall({
      inbox_id: selectedInboxId.value,
      caller_name: callerName.value,
      caller_number: callerNumber.value,
    });
    currentCall.value = response.data;
    sessionStatus.value = 'disconnected';
    sessionError.value = '';
    useAlert(t('VOICE_AI.SETUP.START_SUCCESS'));
  } catch (error) {
    useAlert(error.response?.data?.error || t('VOICE_AI.SETUP.START_ERROR'));
  } finally {
    isCreatingCall.value = false;
  }
};

const clearRemoteAudio = () => {
  const container = remoteAudioRef.value;
  if (!container) return;
  container.replaceChildren();
};

const attachRemoteAudio = track => {
  if (track.kind !== 'audio' || !remoteAudioRef.value) return;
  const element = track.attach();
  element.autoplay = true;
  element.dataset.livekitRemoteAudio = 'true';
  remoteAudioRef.value.appendChild(element);
};

const detachRemoteAudio = track => {
  track.detach().forEach(element => element.remove());
};

const disconnectRoom = () => {
  localAudioTrackRef.value?.stop();
  localAudioTrackRef.value = null;
  roomRef.value?.disconnect();
  roomRef.value = null;
  activeParticipantType.value = '';
  clearRemoteAudio();
  if (sessionStatus.value !== 'failed') {
    sessionStatus.value = 'disconnected';
  }
};

const joinRoom = async participantType => {
  if (!canJoin.value) return;

  isJoining.value = true;
  sessionStatus.value = 'connecting';
  sessionError.value = '';
  activeParticipantType.value = participantType;
  try {
    disconnectRoom();
    activeParticipantType.value = participantType;
    const response = await VoiceAPI.createToken(currentCall.value.id, {
      participant_type: participantType,
    });
    const { url, token } = response.data;
    const room = new Room();
    room.on(RoomEvent.TrackSubscribed, attachRemoteAudio);
    room.on(RoomEvent.TrackUnsubscribed, detachRemoteAudio);
    room.on(RoomEvent.Disconnected, () => {
      sessionStatus.value = 'disconnected';
    });

    await room.connect(url, token);
    const audioTrack = await createLocalAudioTrack({
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
    });
    await room.localParticipant.publishTrack(audioTrack);

    roomRef.value = room;
    localAudioTrackRef.value = audioTrack;
    activeParticipantType.value = participantType;
    isMuted.value = false;
    sessionStatus.value = 'connected';
  } catch (error) {
    sessionStatus.value = 'failed';
    sessionError.value = error.message || t('VOICE_AI.SESSION.CONNECT_ERROR');
    useAlert(t('VOICE_AI.SESSION.CONNECT_ERROR'));
    disconnectRoom();
  } finally {
    isJoining.value = false;
    await nextTick();
  }
};

const toggleMute = () => {
  const track = localAudioTrackRef.value;
  if (!track) return;
  isMuted.value = !isMuted.value;
  track.mediaStreamTrack.enabled = !isMuted.value;
};

const refreshCall = async () => {
  if (!currentCall.value?.id) return;

  isRefreshing.value = true;
  try {
    const response = await VoiceAPI.getCall(currentCall.value.id);
    currentCall.value = response.data;
  } finally {
    isRefreshing.value = false;
  }
};

const takeOver = async () => {
  if (!currentCall.value?.id) return;

  isTakingOver.value = true;
  try {
    const response = await VoiceAPI.takeOver(currentCall.value.id);
    currentCall.value = response.data;
    useAlert(t('VOICE_AI.SESSION.TAKE_OVER_SUCCESS'));
  } catch {
    useAlert(t('VOICE_AI.SESSION.ACTION_ERROR'));
  } finally {
    isTakingOver.value = false;
  }
};

const endCall = async () => {
  if (!currentCall.value?.id) return;

  isEnding.value = true;
  try {
    const response = await VoiceAPI.endCall(currentCall.value.id, {
      end_reason: 'browser_test_ended',
    });
    currentCall.value = response.data;
    disconnectRoom();
    useAlert(t('VOICE_AI.SESSION.END_SUCCESS'));
  } catch {
    useAlert(t('VOICE_AI.SESSION.ACTION_ERROR'));
  } finally {
    isEnding.value = false;
  }
};

const openConversation = () => {
  if (conversationRoute.value) router.push(conversationRoute.value);
};

watch(selectedInboxId, () => {
  syncFormFromSetting(selectedSetting.value);
});

onMounted(loadData);
onBeforeUnmount(disconnectRoom);
</script>

<template>
  <SettingsLayout :is-loading="isLoading">
    <template #header>
      <BaseSettingsHeader
        :title="t('VOICE_AI.HEADER')"
        :description="t('VOICE_AI.DESCRIPTION')"
        feature-name="voice_ai"
      />
    </template>

    <template #body>
      <div class="grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_360px] gap-6">
        <section
          class="rounded-xl border border-n-weak bg-n-solid-1 p-5 flex flex-col gap-5"
        >
          <div>
            <h2 class="text-heading-2 text-n-slate-12">
              {{ t('VOICE_AI.SETUP.TITLE') }}
            </h2>
            <p class="mb-0 mt-1 text-sm text-n-slate-11">
              {{ t('VOICE_AI.SETUP.DESCRIPTION') }}
            </p>
          </div>

          <div v-if="!apiInboxes.length" class="text-sm text-n-ruby-9">
            {{ t('VOICE_AI.SETUP.NO_API_INBOX') }}
          </div>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <label class="flex flex-col gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('VOICE_AI.SETUP.INBOX') }}
              </span>
              <select
                v-model="selectedInboxId"
                class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12"
              >
                <option value="" disabled>
                  {{ t('VOICE_AI.SETUP.INBOX') }}
                </option>
                <option
                  v-for="inbox in apiInboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
                  {{ inbox.name }}
                </option>
              </select>
            </label>

            <label class="flex flex-col gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('VOICE_AI.SETUP.AI_AGENT') }}
              </span>
              <select
                v-model="selectedAiAgentId"
                class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12"
              >
                <option value="">
                  {{ t('VOICE_AI.SETUP.NONE') }}
                </option>
                <option
                  v-for="agent in aiAgents"
                  :key="agent.id"
                  :value="agent.id"
                >
                  {{ agent.name }}
                </option>
              </select>
            </label>

            <label class="flex flex-col gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('VOICE_AI.SETUP.FALLBACK_TEAM') }}
              </span>
              <select
                v-model="selectedFallbackTeamId"
                class="h-10 rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12"
              >
                <option value="">
                  {{ t('VOICE_AI.SETUP.NONE') }}
                </option>
                <option v-for="team in teams" :key="team.id" :value="team.id">
                  {{ team.name }}
                </option>
              </select>
            </label>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Input v-model="greeting" :label="t('VOICE_AI.SETUP.GREETING')" />
            <Input
              v-model="callerName"
              :label="t('VOICE_AI.SETUP.CALLER_NAME')"
            />
            <Input
              v-model="callerNumber"
              :label="t('VOICE_AI.SETUP.CALLER_NUMBER')"
            />
          </div>

          <label class="flex flex-col gap-1">
            <span class="text-heading-3 text-n-slate-12">
              {{ t('VOICE_AI.SETUP.INSTRUCTIONS') }}
            </span>
            <textarea
              v-model="instructions"
              rows="6"
              class="rounded-lg border-0 outline outline-1 outline-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 resize-y"
            />
          </label>

          <div class="flex flex-wrap gap-3">
            <Button
              :label="t('VOICE_AI.SETUP.SAVE')"
              icon="i-lucide-save"
              variant="outline"
              color="slate"
              :disabled="!canSave"
              :is-loading="isSaving"
              @click="saveSettings"
            />
            <Button
              :label="t('VOICE_AI.SETUP.START_TEST')"
              icon="i-lucide-phone-call"
              :disabled="!canStartTest"
              :is-loading="isCreatingCall"
              @click="createTestCall"
            />
          </div>
        </section>

        <aside
          class="rounded-xl border border-n-weak bg-n-solid-1 p-5 flex flex-col gap-4"
        >
          <div>
            <h2 class="text-heading-2 text-n-slate-12">
              {{ t('VOICE_AI.SESSION.TITLE') }}
            </h2>
            <p class="mb-0 mt-1 text-sm text-n-slate-11">
              {{
                hasCall
                  ? currentCall.livekit_room_name
                  : t('VOICE_AI.SESSION.NOT_STARTED')
              }}
            </p>
          </div>

          <dl
            class="grid grid-cols-[96px_minmax(0,1fr)] gap-x-3 gap-y-2 text-sm"
          >
            <dt class="text-n-slate-11">{{ t('VOICE_AI.SESSION.STATUS') }}</dt>
            <dd class="text-n-slate-12">{{ sessionStatusLabel }}</dd>
            <dt class="text-n-slate-11">{{ t('VOICE_AI.SESSION.ROOM') }}</dt>
            <dd class="truncate text-n-slate-12">
              {{ currentCall?.livekit_room_name || '-' }}
            </dd>
          </dl>

          <p v-if="sessionError" class="mb-0 text-sm text-n-ruby-9">
            {{ sessionError }}
          </p>

          <div ref="remoteAudioRef" class="hidden" />

          <div class="grid grid-cols-1 gap-2">
            <Button
              :label="t('VOICE_AI.SESSION.JOIN_CALLER')"
              icon="i-lucide-user"
              :disabled="!canJoin || isConnected"
              :is-loading="isJoining && activeParticipantType === 'caller'"
              @click="joinRoom('caller')"
            />
            <Button
              :label="t('VOICE_AI.SESSION.JOIN_AGENT')"
              icon="i-lucide-headphones"
              variant="outline"
              color="slate"
              :disabled="!canJoin || isConnected"
              :is-loading="isJoining && activeParticipantType === 'agent'"
              @click="joinRoom('agent')"
            />
            <Button
              :label="
                isMuted
                  ? t('VOICE_AI.SESSION.UNMUTE')
                  : t('VOICE_AI.SESSION.MUTE')
              "
              icon="i-lucide-mic"
              variant="outline"
              color="slate"
              :disabled="!isConnected"
              @click="toggleMute"
            />
            <Button
              :label="t('VOICE_AI.SESSION.DISCONNECT')"
              icon="i-lucide-phone-off"
              variant="outline"
              color="ruby"
              :disabled="!isConnected"
              @click="disconnectRoom"
            />
          </div>

          <div class="h-px bg-n-weak" />

          <div class="grid grid-cols-1 gap-2">
            <Button
              :label="t('VOICE_AI.SESSION.TAKE_OVER')"
              icon="i-lucide-user-check"
              variant="outline"
              color="slate"
              :disabled="!hasCall"
              :is-loading="isTakingOver"
              @click="takeOver"
            />
            <Button
              :label="t('VOICE_AI.SESSION.REFRESH')"
              icon="i-lucide-refresh-cw"
              variant="outline"
              color="slate"
              :disabled="!hasCall"
              :is-loading="isRefreshing"
              @click="refreshCall"
            />
            <Button
              :label="t('VOICE_AI.SESSION.OPEN_CONVERSATION')"
              icon="i-lucide-message-square"
              variant="outline"
              color="slate"
              :disabled="!conversationRoute"
              @click="openConversation"
            />
            <Button
              :label="t('VOICE_AI.SESSION.END_CALL')"
              icon="i-lucide-circle-stop"
              variant="outline"
              color="ruby"
              :disabled="!hasCall"
              :is-loading="isEnding"
              @click="endCall"
            />
          </div>
        </aside>

        <section
          class="xl:col-span-2 rounded-xl border border-n-weak bg-n-solid-1 p-5"
        >
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-heading-2 text-n-slate-12">
              {{ t('VOICE_AI.TRANSCRIPT.TITLE') }}
            </h2>
            <span class="text-sm text-n-slate-11">
              {{ transcriptSegments.length }}
            </span>
          </div>

          <div
            v-if="!transcriptSegments.length"
            class="mt-4 rounded-lg bg-n-alpha-2 p-4 text-sm text-n-slate-11"
          >
            {{ t('VOICE_AI.TRANSCRIPT.EMPTY') }}
          </div>
          <div v-else class="mt-4 flex flex-col gap-3">
            <div
              v-for="segment in transcriptSegments"
              :key="segment.id"
              class="rounded-lg bg-n-alpha-2 p-3"
            >
              <div class="mb-1 flex items-center justify-between gap-3">
                <span class="text-sm font-medium text-n-slate-12 capitalize">
                  {{ segment.role }}
                </span>
                <span class="text-xs text-n-slate-10">
                  {{ segment.source }}
                </span>
              </div>
              <p class="mb-0 whitespace-pre-wrap text-sm text-n-slate-12">
                {{ segment.text }}
              </p>
            </div>
          </div>
        </section>
      </div>
    </template>
  </SettingsLayout>
</template>
