import { setActivePinia, createPinia } from 'pinia';
import { useCallsStore } from './calls';
import TwilioVoiceClient from 'dashboard/api/channel/voice/twilioVoiceClient';
import { cleanupWhatsappSession } from 'dashboard/composables/useWhatsappCallSession';

vi.mock('dashboard/api/channel/voice/twilioVoiceClient', () => ({
  default: {
    endClientCall: vi.fn(),
  },
}));

vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  cleanupWhatsappSession: vi.fn(),
}));

describe('calls store', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  describe('teardownByProvider', () => {
    it('does not call TwilioVoiceClient when call is undefined', () => {
      const store = useCallsStore();
      store.clearActiveCall();
      expect(TwilioVoiceClient.endClientCall).not.toHaveBeenCalled();
    });

    it('does not call TwilioVoiceClient for LiveKit calls', () => {
      const store = useCallsStore();
      store.calls = [{ callSid: 'lk-1', provider: 'livekit', isActive: true }];
      store.clearActiveCall();
      expect(TwilioVoiceClient.endClientCall).not.toHaveBeenCalled();
      expect(cleanupWhatsappSession).not.toHaveBeenCalled();
    });

    it('calls TwilioVoiceClient for legacy (twilio) calls', () => {
      const store = useCallsStore();
      store.calls = [{ callSid: 'tw-1', provider: 'twilio', isActive: true }];
      store.clearActiveCall();
      expect(TwilioVoiceClient.endClientCall).toHaveBeenCalledTimes(1);
    });

    it('calls cleanupWhatsappSession for WhatsApp calls', () => {
      const store = useCallsStore();
      store.calls = [{ callSid: 'wa-1', provider: 'whatsapp', isActive: true }];
      store.clearActiveCall();
      expect(cleanupWhatsappSession).toHaveBeenCalledTimes(1);
      expect(TwilioVoiceClient.endClientCall).not.toHaveBeenCalled();
    });
  });

  describe('clearActiveCall', () => {
    it('removes the active call from state', () => {
      const store = useCallsStore();
      store.calls = [
        { callSid: 'lk-1', provider: 'livekit', isActive: true },
        { callSid: 'lk-2', provider: 'livekit', isActive: false },
      ];
      store.clearActiveCall();
      expect(store.calls).toHaveLength(1);
      expect(store.calls[0].callSid).toBe('lk-2');
    });

    it('is safe when no calls are active', () => {
      const store = useCallsStore();
      store.calls = [{ callSid: 'lk-1', provider: 'livekit', isActive: false }];
      store.clearActiveCall();
      expect(store.calls).toHaveLength(1);
      expect(TwilioVoiceClient.endClientCall).not.toHaveBeenCalled();
    });
  });

  describe('addCall', () => {
    it('preserves existing startedAt when a later payload omits it', () => {
      const store = useCallsStore();
      store.addCall({
        callSid: 'lk-1',
        provider: 'livekit',
        startedAt: '2026-06-29T20:51:35Z',
      });
      store.addCall({
        callSid: 'lk-1',
        provider: 'livekit',
        status: 'ringing',
      });

      expect(store.calls[0]).toMatchObject({
        callSid: 'lk-1',
        status: 'ringing',
        startedAt: '2026-06-29T20:51:35Z',
      });
    });
  });

  describe('removeCallsForConversation', () => {
    it('tears down active calls by provider before removing', () => {
      const store = useCallsStore();
      store.calls = [
        {
          callSid: 'tw-1',
          provider: 'twilio',
          isActive: true,
          conversationId: 1,
        },
        {
          callSid: 'wa-1',
          provider: 'whatsapp',
          isActive: true,
          conversationId: 1,
        },
        {
          callSid: 'lk-1',
          provider: 'livekit',
          isActive: true,
          conversationId: 1,
        },
      ];
      store.removeCallsForConversation(1);
      expect(TwilioVoiceClient.endClientCall).toHaveBeenCalledTimes(1);
      expect(cleanupWhatsappSession).toHaveBeenCalledTimes(1);
      expect(store.calls).toHaveLength(0);
    });
  });
});
