import { computed, nextTick, onBeforeUnmount, ref } from 'vue';
import { Room, RoomEvent, createLocalAudioTrack } from 'livekit-client';
import { useI18n } from 'vue-i18n';

import VoiceAPI from 'dashboard/api/voice';

const CLIENT_SESSION_STORAGE_KEY = 'kozmopath:voice:client-session-id';
const JOIN_TIMEOUT_MS = 30000;

const randomSessionId = () => {
  if (window.crypto?.randomUUID) return window.crypto.randomUUID();
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
};

const getClientSessionId = () => {
  try {
    const existing = window.sessionStorage.getItem(CLIENT_SESSION_STORAGE_KEY);
    if (existing) return existing;

    const id = randomSessionId();
    window.sessionStorage.setItem(CLIENT_SESSION_STORAGE_KEY, id);
    return id;
  } catch {
    return randomSessionId();
  }
};

const withTimeout = (promise, timeoutMs, message) => {
  let timeoutId;
  const timeout = new Promise((_, reject) => {
    timeoutId = window.setTimeout(() => reject(new Error(message)), timeoutMs);
  });

  return Promise.race([promise, timeout]).finally(() => {
    window.clearTimeout(timeoutId);
  });
};

export function useLivekitVoiceSession({ call }) {
  const { t } = useI18n();

  const sessionStatus = ref('disconnected');
  const sessionError = ref('');
  const activeParticipantType = ref('');
  const isJoining = ref(false);
  const isMuted = ref(false);
  const remoteAudioRef = ref(null);
  const roomRef = ref(null);
  const localAudioTrackRef = ref(null);

  const currentCall = computed(() => call?.value || null);
  const isConnected = computed(() => sessionStatus.value === 'connected');

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

  const cleanupMedia = () => {
    localAudioTrackRef.value?.stop();
    localAudioTrackRef.value = null;
    activeParticipantType.value = '';
    clearRemoteAudio();
  };

  const disconnectRoom = () => {
    const room = roomRef.value;
    roomRef.value = null;
    room?.disconnect();
    cleanupMedia();
    if (sessionStatus.value !== 'failed') {
      sessionStatus.value = 'disconnected';
    }
  };

  const joinRoom = async participantType => {
    if (!currentCall.value?.id || isJoining.value) return false;

    isJoining.value = true;
    sessionStatus.value = 'connecting';
    sessionError.value = '';
    activeParticipantType.value = participantType;
    try {
      disconnectRoom();
      activeParticipantType.value = participantType;
      const response = await withTimeout(
        VoiceAPI.createToken(currentCall.value.id, {
          participant_type: participantType,
          client_session_id: getClientSessionId(),
        }),
        JOIN_TIMEOUT_MS,
        t('VOICE_AI.SESSION.CONNECT_ERROR')
      );
      const { url, token } = response.data;
      const room = new Room();
      roomRef.value = room;
      room.on(RoomEvent.TrackSubscribed, attachRemoteAudio);
      room.on(RoomEvent.TrackUnsubscribed, detachRemoteAudio);
      room.on(RoomEvent.Disconnected, () => {
        if (roomRef.value !== room) return;
        roomRef.value = null;
        cleanupMedia();
        sessionStatus.value = 'disconnected';
      });

      await withTimeout(
        room.connect(url, token),
        JOIN_TIMEOUT_MS,
        t('VOICE_AI.SESSION.CONNECT_ERROR')
      );
      const audioTrack = await withTimeout(
        createLocalAudioTrack({
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        }),
        JOIN_TIMEOUT_MS,
        t('VOICE_AI.SESSION.CONNECT_ERROR')
      );
      await withTimeout(
        room.localParticipant.publishTrack(audioTrack),
        JOIN_TIMEOUT_MS,
        t('VOICE_AI.SESSION.CONNECT_ERROR')
      );

      localAudioTrackRef.value = audioTrack;
      activeParticipantType.value = participantType;
      isMuted.value = false;
      sessionStatus.value = 'connected';
      return true;
    } catch (error) {
      sessionStatus.value = 'failed';
      sessionError.value = error.message || t('VOICE_AI.SESSION.CONNECT_ERROR');
      disconnectRoom();
      return false;
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

  onBeforeUnmount(disconnectRoom);

  return {
    remoteAudioRef,
    sessionStatus,
    sessionError,
    activeParticipantType,
    isJoining,
    isMuted,
    isConnected,
    joinRoom,
    disconnectRoom,
    toggleMute,
  };
}
