import { mount } from '@vue/test-utils';
import VoiceTranscriptSegment from '../VoiceTranscriptSegment.vue';

const translations = {
  'CONVERSATION.VOICE_CALL.TRANSCRIPT_CALLER': 'Caller',
  'CONVERSATION.VOICE_CALL.TRANSCRIPT_AI': 'AI',
  'CONVERSATION.VOICE_CALL.TRANSCRIPT_AGENT': 'Agent',
  'CONVERSATION.VOICE_CALL.MACHINE_TRANSCRIPT': 'Machine transcript',
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => translations[key] || key,
  }),
}));

const mountComponent = props =>
  mount(VoiceTranscriptSegment, {
    props,
  });

describe('VoiceTranscriptSegment', () => {
  it('renders caller transcript as machine transcript', () => {
    const wrapper = mountComponent({
      segment: {
        id: 1,
        role: 'caller',
        text: 'Merhaba',
        createdAt: '2026-06-20T12:00:00Z',
      },
    });

    expect(wrapper.text()).toContain('Caller');
    expect(wrapper.text()).toContain('Merhaba');
    expect(wrapper.text()).toContain('Machine transcript');
    expect(wrapper.classes()).toContain('justify-start');
  });

  it('uses the selected voice agent name for assistant transcript', () => {
    const wrapper = mountComponent({
      voiceAgentName: 'Kamataş Assistant',
      segment: {
        id: 2,
        role: 'ai',
        text: 'Size nasıl yardımcı olabilirim?',
        createdAt: '2026-06-20T12:01:00Z',
      },
    });

    expect(wrapper.text()).toContain('Kamataş Assistant');
    expect(wrapper.text()).toContain('Size nasıl yardımcı olabilirim?');
    expect(wrapper.classes()).toContain('justify-end');
  });
});
