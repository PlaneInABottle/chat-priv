import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';

import VoiceCall from '../bubbles/VoiceCall.vue';
import VoiceAPI from 'dashboard/api/voice';

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
const voiceSession = vi.hoisted(() => ({
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
const callsStore = vi.hoisted(() => ({
  hasIncomingCall: false,
  activeCall: null,
  addCall: vi.fn(),
  setCallActive: vi.fn(),
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

vi.mock('dashboard/composables/useVoiceSession', () => ({
  useVoiceSession: () => voiceSession,
}));

vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: () => ({
    initiateOutboundCall: vi.fn(),
  }),
}));

vi.mock('dashboard/stores/calls', () => ({
  useCallsStore: () => callsStore,
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
  beforeEach(() => {
    vi.clearAllMocks();
    callsStore.hasIncomingCall = false;
    callsStore.activeCall = null;
    callActions.activeCall.value = null;
    callActions.hasActiveCall.value = false;
    VoiceAPI.getCall.mockImplementation(() => new Promise(() => {}));
  });

  it('uses failed copy for a stale active recording on a completed call', () => {
    const wrapper = mountComponent({
      id: 3,
      provider: 'kozmopath_voice',
      callReference: 'browser-recording-b1b47ada',
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
      provider: 'kozmopath_voice',
      callReference: 'recent-room',
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
      provider: 'kozmopath_voice',
      callReference: 'live-room',
      direction: 'incoming',
      status: 'in-progress',
      recording: { status: 'active' },
    });

    expect(wrapper.text()).toContain('Call in progress');
    expect(wrapper.text()).toContain('Recording is processing');
  });

  it('shows one takeover action for a live handoff call', () => {
    const wrapper = mountComponent({
      id: 7,
      provider: 'kozmopath_voice',
      callReference: 'handoff-room',
      direction: 'incoming',
      status: 'in-progress',
      handoffStatus: 'requested',
    });

    const labels = wrapper
      .findAll('next-button-stub')
      .map(button => button.attributes('label'));

    expect(labels.filter(label => label === 'Take over')).toHaveLength(1);
    expect(labels).not.toContain('Join live call');
  });

  it('does not expose local disconnect for an active Kozmopath Voice call', () => {
    callActions.activeCall.value = {
      provider: 'kozmopath_voice',
      callSid: 'active-room',
    };

    const wrapper = mountComponent({
      id: 9,
      provider: 'kozmopath_voice',
      callReference: 'active-room',
      direction: 'incoming',
      status: 'in-progress',
      handoffStatus: 'accepted',
      aiStatus: 'silent',
    });

    const labels = wrapper
      .findAll('next-button-stub')
      .map(button => button.attributes('label'));

    expect(labels).toContain('End call');
    expect(labels).not.toContain('Disconnect');
    expect(labels).not.toContain('Join live call');
    expect(labels).not.toContain('Take over');
  });

  it('does not activate the call widget when refresh says the call already ended', async () => {
    VoiceAPI.getCall.mockResolvedValueOnce({
      data: {
        id: 8,
        provider: 'kozmopath_voice',
        call_reference: 'ended-room',
        status: 'completed',
      },
    });
    const wrapper = mountComponent({
      id: 8,
      provider: 'kozmopath_voice',
      callReference: 'ended-room',
      direction: 'incoming',
      status: 'in-progress',
    });

    const takeoverButton = wrapper
      .findAll('next-button-stub')
      .find(button => button.attributes('label') === 'Take over');
    await takeoverButton.trigger('click');
    await flushPromises();

    expect(VoiceAPI.getCall).toHaveBeenCalledWith(8);
    expect(callsStore.addCall).not.toHaveBeenCalled();
    expect(callsStore.setCallActive).not.toHaveBeenCalled();
  });
});
