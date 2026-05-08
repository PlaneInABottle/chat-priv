import { flushPromises, mount } from '@vue/test-utils';
import AiAgentToolLogs from '../AiAgentToolLogs.vue';
import ToolLogsTable from 'dashboard/components-next/AI/ToolLogsTable.vue';
import aiAgentAPI from 'dashboard/api/aiAgent';

vi.mock('dashboard/api/aiAgent', () => ({
  default: {
    getToolExecutions: vi.fn(),
  },
}));

const mountComponent = () =>
  mount(AiAgentToolLogs, {
    props: { aiAgentId: 1 },
    global: { mocks: { $t: key => key } },
  });

describe('AiAgentToolLogs', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('passes fetched rows to the shared table', async () => {
    aiAgentAPI.getToolExecutions.mockResolvedValue({
      data: { payload: [{ id: 1, tool_key: 'human_handoff' }] },
    });

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.findComponent(ToolLogsTable).props('rows')).toEqual([
      { id: 1, tool_key: 'human_handoff' },
    ]);
  });

  it('fetches when filters change', async () => {
    aiAgentAPI.getToolExecutions.mockResolvedValue({ data: { payload: [] } });

    const wrapper = mountComponent();
    await flushPromises();
    wrapper.findComponent(ToolLogsTable).vm.$emit('update:filters', {
      status: 'error',
    });
    await flushPromises();

    expect(aiAgentAPI.getToolExecutions).toHaveBeenLastCalledWith(
      1,
      expect.objectContaining({ status: 'error' })
    );
  });

  it('fetches when sort changes', async () => {
    aiAgentAPI.getToolExecutions.mockResolvedValue({ data: { payload: [] } });

    const wrapper = mountComponent();
    await flushPromises();
    wrapper.findComponent(ToolLogsTable).vm.$emit('update:sort', {
      sort: 'duration_ms',
      direction: 'asc',
    });
    await flushPromises();

    expect(aiAgentAPI.getToolExecutions).toHaveBeenLastCalledWith(
      1,
      expect.objectContaining({ sort: 'duration_ms', direction: 'asc' })
    );
  });

  it('passes API errors to the shared table', async () => {
    aiAgentAPI.getToolExecutions.mockRejectedValue(new Error('failed'));

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.findComponent(ToolLogsTable).props('error')).toBe(
      'Failed to load tool logs.'
    );
  });
});
