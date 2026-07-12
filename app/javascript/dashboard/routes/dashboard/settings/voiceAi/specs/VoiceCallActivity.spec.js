import { flushPromises, mount } from '@vue/test-utils';
import VoiceCallActivity from '../VoiceCallActivity.vue';

const mocks = vi.hoisted(() => ({
  getCalls: vi.fn(),
  push: vi.fn(),
}));

vi.mock('dashboard/api/voice', () => ({
  default: { getCalls: mocks.getCalls },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '51' } }),
  useRouter: () => ({ push: mocks.push }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) => {
      if (key.endsWith('.CONVERSATION')) {
        return `Conversation #${values.id}`;
      }
      if (key.endsWith('.OUTCOME.HUMAN_HANDOFF')) return 'Human handoff';
      if (key.endsWith('.HANDOFF.ACCEPTED')) return 'Accepted';
      if (key.endsWith('.RECORDING.COMPLETED')) return 'Available';
      return key;
    },
  }),
}));

const call = {
  id: 19,
  conversation_id: 72,
  outcome: 'human_handoff',
  status: 'completed',
  from_number: '+905551112233',
  inbox: { id: 4, name: 'Phone support' },
  voice_agent: { id: 8, name: 'Order assistant', revision: 2 },
  handoff_status: 'accepted',
  started_at: '2026-07-12T09:00:00Z',
  duration_seconds: 75,
  summary: '**Customer** asked for an order update and was transferred.',
  transcript_count: 6,
  action_count: 2,
  action_error_count: 1,
  recording_status: 'completed',
};

const mountComponent = () =>
  mount(VoiceCallActivity, {
    props: { voiceAgents: [{ id: 8, name: 'Order assistant' }] },
    global: {
      stubs: {
        Button: {
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
          props: ['label'],
          emits: ['click'],
        },
        Input: {
          template: '<input />',
          props: ['modelValue', 'label'],
        },
      },
    },
  });

describe('VoiceCallActivity.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getCalls.mockResolvedValue({ data: [call] });
  });

  it('renders owner-facing call evidence', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(mocks.getCalls).toHaveBeenCalledWith({ limit: 25 });
    expect(wrapper.text()).toContain('Conversation #72');
    expect(wrapper.text()).toContain('Human handoff');
    expect(wrapper.text()).toContain('Customer asked for an order update');
    expect(wrapper.text()).not.toContain('**Customer**');
    expect(wrapper.text()).toContain('+905551112233');
    expect(wrapper.text()).toContain('1m 15s');
    expect(wrapper.text()).toContain('6');
    expect(wrapper.text()).toContain('Available');
  });

  it('opens the related conversation', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    wrapper.vm.openConversation(call);

    expect(mocks.push).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { accountId: '51', conversation_id: 72 },
    });
  });

  it('sends selected filters without blank values', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.filters = {
      status: 'failed',
      handoff_status: '',
      voice_agent_id: 8,
      phone: '',
      limit: 10,
    };
    wrapper.vm.showFilters = true;

    await wrapper.vm.applyFilters();

    expect(mocks.getCalls).toHaveBeenLastCalledWith({
      status: 'failed',
      voice_agent_id: 8,
      limit: 10,
    });
    expect(wrapper.vm.showFilters).toBe(false);
  });
});
