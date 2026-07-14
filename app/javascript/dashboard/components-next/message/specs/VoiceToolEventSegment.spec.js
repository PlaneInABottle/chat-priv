import { mount } from '@vue/test-utils';
import VoiceToolEventSegment from '../VoiceToolEventSegment.vue';

const translations = {
  'CONVERSATION.VOICE_CALL.TRANSCRIPT_AI': 'AI',
  'CONVERSATION.VOICE_CALL.TOOL_IKAS_CATALOG_SEARCH':
    '{agent} searched the ikas catalog',
  'CONVERSATION.VOICE_CALL.TOOL_HUMAN_HANDOFF':
    '{agent} requested human handoff',
  'CONVERSATION.VOICE_CALL.TOOL_USED': '{agent} completed an action',
  'CONVERSATION.VOICE_CALL.TOOL_STARTED': 'started',
  'CONVERSATION.VOICE_CALL.TOOL_EXECUTED': 'done',
  'CONVERSATION.VOICE_CALL.TOOL_ERROR': 'failed',
  'CONVERSATION.VOICE_CALL.TOOL_REJECTED': 'rejected',
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) =>
      Object.keys(values).reduce(
        (text, valueKey) => text.replace(`{${valueKey}}`, values[valueKey]),
        translations[key] || key
      ),
  }),
}));

const mountComponent = event =>
  mount(VoiceToolEventSegment, {
    props: {
      voiceAgentName: 'Voice Assistant',
      event,
    },
  });

describe('VoiceToolEventSegment', () => {
  it('renders a readable catalog search event', () => {
    const wrapper = mountComponent({
      id: 1,
      action: 'catalog_search',
      status: 'executed',
      createdAt: '2026-06-20T12:00:00Z',
    });

    expect(wrapper.text()).toContain(
      'Voice Assistant searched the ikas catalog'
    );
    expect(wrapper.text()).toContain('done');
    expect(wrapper.find('article').classes()).toContain('bg-n-teal-2');
  });

  it('renders failed tool events distinctly', () => {
    const wrapper = mountComponent({
      id: 2,
      action: 'human_handoff',
      status: 'error',
      errorMessage: 'handoff unavailable',
      arguments: { reason: 'private reason' },
      result: { internalNote: 'private note' },
      createdAt: '2026-06-20T12:01:00Z',
    });

    expect(wrapper.text()).toContain('Voice Assistant requested human handoff');
    expect(wrapper.text()).toContain('failed');
    expect(wrapper.text()).not.toMatch(
      /handoff unavailable|private reason|private note/
    );
    expect(wrapper.find('article').classes()).toContain('bg-n-ruby-2');
  });

  it('does not expose an unknown internal tool name', () => {
    const wrapper = mountComponent({
      id: 3,
      action: 'generic',
      status: 'executed',
      createdAt: '2026-06-20T12:02:00Z',
    });

    expect(wrapper.text()).toContain('Voice Assistant completed an action');
    expect(wrapper.text()).not.toContain('generic');
  });
});
