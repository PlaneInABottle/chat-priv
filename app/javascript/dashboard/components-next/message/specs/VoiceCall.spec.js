import { mount } from '@vue/test-utils';
import { ref } from 'vue';

import VoiceCall from '../bubbles/VoiceCall.vue';

const contextState = vi.hoisted(() => ({ context: null }));
const contactsUiFlags = vi.hoisted(() => ({
  value: { isInitiatingCall: false },
}));
const callActions = vi.hoisted(() => ({
  joinCall: vi.fn(),
  endCall: vi.fn(),
  dismissCall: vi.fn(),
  activeCall: { value: null },
  hasActiveCall: { value: false },
  isJoining: { value: false },
}));
const livekitSession = vi.hoisted(() => ({
  remoteAudioRef: { __v_isRef: true, value: null },
  sessionStatus: { value: 'disconnected' },
  sessionError: { value: '' },
  activeParticipantType: { value: null },
  isJoining: { value: false },
  isMuted: { value: false },
  isConnected: { value: false },
  joinRoom: vi.fn(),
  disconnectRoom: vi.fn(),
  toggleMute: vi.fn(),
}));

const translations = {
  'CONVERSATION.VOICE_CALL.CALL_ENDED': 'Call ended',
  'CONVERSATION.VOICE_CALL.CALL_IN_PROGRESS': 'Call in progress',
  'CONVERSATION.VOICE_CALL.RECORDING_PROCESSING': 'Recording is processing',
  'CONVERSATION.VOICE_CALL.RECORDING_FAILED': 'Recording failed',
  'CONVERSATION.VOICE_CALL.SUMMARY': 'Call summary',
  'CONVERSATION.VOICE_CALL.AI_ACTIVE': 'AI is handling the call',
  'CONVERSATION.VOICE_CALL.LIVE_BADGE': 'Live',
  'CONVERSATION.VOICE_CALL.LIVE_SESSION': 'Live session',
  'CONVERSATION.VOICE_CALL.JOIN_LIVE_CALL': 'Join live call',
  'CONVERSATION.VOICE_CALL.TAKE_OVER': 'Take over',
  'CONVERSATION.VOICE_CALL.END_CALL': 'End call',
  'CONVERSATION.VOICE_CALL.MUTE': 'Mute',
  'CONVERSATION.VOICE_CALL.UNMUTE': 'Unmute',
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => translations[key] || key,
  }),
}));

vi.mock('../provider.js', () => ({
  useMessageContext: () => contextState.context,
}));

vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      getConversationById: () => ({ meta: {} }),
      'agents/getAgentById': () => null,
    },
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => contactsUiFlags,
}));

vi.mock('dashboard/composables/useCallSession', () => ({
  useCallActions: () => callActions,
}));

vi.mock('dashboard/composables/useLivekitVoiceSession', () => ({
  useLivekitVoiceSession: () => livekitSession,
}));

vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: () => ({
    initiateOutboundCall: vi.fn(),
  }),
}));

vi.mock('dashboard/stores/calls', () => ({
  useCallsStore: () => ({
    hasIncomingCall: false,
    addCall: vi.fn(),
  }),
}));

vi.mock('dashboard/api/voice', () => ({
  default: {
    getCall: vi.fn(() => new Promise(() => {})),
    takeOver: vi.fn(),
    endCall: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const buildContext = call => ({
  call: ref(call),
  attachments: ref([]),
  contentAttributes: ref({ data: {} }),
  conversationId: ref(5),
  currentUserId: ref(1),
  inboxId: ref(74),
  sender: ref({ id: 52, name: 'Customer' }),
  messageType: ref(0),
});

const mountComponent = call => {
  contextState.context = buildContext(call);

  return mount(VoiceCall, {
    global: {
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        Icon: true,
        AudioChip: true,
        NextButton: true,
      },
    },
  });
};

describe('VoiceCall', () => {
  it('uses failed copy for a stale active recording on a completed call', () => {
    const wrapper = mountComponent({
      id: 3,
      provider: 'livekit',
      providerCallId: 'browser-recording-b1b47ada',
      direction: 'incoming',
      status: 'completed',
      updatedAt: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
      durationSeconds: 74,
      recording: {
        status: 'active',
        updatedAt: new Date().toISOString(),
      },
      summary: { text: 'Customer requested a human handoff.' },
    });

    expect(wrapper.text()).toContain('Call ended');
    expect(wrapper.text()).toContain('Recording failed');
    expect(wrapper.text()).not.toContain('Recording is processing');
    expect(wrapper.text()).toContain('Customer requested a human handoff.');
  });

  it('keeps processing copy for a recently ended call while recording settles', () => {
    const wrapper = mountComponent({
      id: 5,
      provider: 'livekit',
      providerCallId: 'recent-room',
      direction: 'incoming',
      status: 'completed',
      updatedAt: new Date(Date.now() - 30 * 1000).toISOString(),
      durationSeconds: 30,
      recording: {
        status: 'active',
        updatedAt: new Date().toISOString(),
      },
    });

    expect(wrapper.text()).toContain('Call ended');
    expect(wrapper.text()).toContain('Recording is processing');
  });

  it('keeps processing copy for an active recording on a live call', () => {
    const wrapper = mountComponent({
      id: 4,
      provider: 'livekit',
      providerCallId: 'live-room',
      direction: 'incoming',
      status: 'in-progress',
      recording: { status: 'active' },
    });

    expect(wrapper.text()).toContain('Call in progress');
    expect(wrapper.text()).toContain('Recording is processing');
  });
});
