import { flushPromises, mount } from '@vue/test-utils';
import AiAgentToolLogs from '../AiAgentToolLogs.vue';
import aiAgentAPI from 'dashboard/api/aiAgent';

vi.mock('dashboard/api/aiAgent', () => ({
  default: {
    getToolExecutions: vi.fn(),
  },
}));

const mountComponent = () => mount(AiAgentToolLogs, {
  props: { aiAgentId: 1 },
  global: { mocks: { $t: key => key } },
});

describe('AiAgentToolLogs', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders the empty state', async () => {
    aiAgentAPI.getToolExecutions.mockResolvedValue({ data: { payload: [] } });

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('No tool executions yet.');
  });

  it('renders populated logs with conversation link and JSON details', async () => {
    aiAgentAPI.getToolExecutions.mockResolvedValue({ data: { payload: [{ id: 1, tool_key: 'human_handoff', mode: 'test', status: 'executed', created_at: 'now', conversation_url: '/app/accounts/1/conversations/2', conversation_display_id: 2, arguments: { reason: 'Help' }, result: { status: 'ok' } }] } });

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('human_handoff');
    expect(wrapper.find('a').attributes('href')).toBe('/app/accounts/1/conversations/2');
    expect(wrapper.text()).toContain('Help');
  });

  it('sends filters to the API', async () => {
    aiAgentAPI.getToolExecutions.mockResolvedValue({ data: { payload: [] } });

    const wrapper = mountComponent();
    await flushPromises();
    await wrapper.find('select').setValue('error');
    await flushPromises();

    expect(aiAgentAPI.getToolExecutions).toHaveBeenLastCalledWith(1, expect.objectContaining({ status: 'error' }));
  });

  it('renders errors', async () => {
    aiAgentAPI.getToolExecutions.mockRejectedValue(new Error('failed'));

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('Failed to load tool logs.');
  });
});
