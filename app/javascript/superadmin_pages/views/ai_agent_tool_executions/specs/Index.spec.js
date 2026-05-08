import { flushPromises, mount } from '@vue/test-utils';
import Index from '../Index.vue';
import ToolLogsTable from 'dashboard/components-next/AI/ToolLogsTable.vue';

const componentData = {
  initial_payload: {
    meta: { filters: { sort: 'created_at', direction: 'desc' } },
    payload: [{ id: 1, account_name: 'Acme', tool_key: 'human_handoff' }],
  },
  tool_options: [{ key: 'human_handoff', name: 'human_handoff' }],
  account_options: [{ id: 1, name: 'Acme' }],
};

const mountComponent = () => mount(Index, { props: { componentData } });

describe('SuperAdmin AiAgentToolExecutions Index', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('passes initial payload to shared table with account column enabled', () => {
    const wrapper = mountComponent();

    expect(wrapper.findComponent(ToolLogsTable).props('rows')).toEqual(
      componentData.initial_payload.payload
    );
    expect(wrapper.findComponent(ToolLogsTable).props('showAccountColumn')).toBe(
      true
    );
  });

  it('fetches JSON when filters change', async () => {
    vi.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ meta: { filters: {} }, payload: [] }),
    });
    const wrapper = mountComponent();

    wrapper.findComponent(ToolLogsTable).vm.$emit('update:filters', {
      account_id: 1,
    });
    await flushPromises();

    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining('account_id=1'),
      expect.any(Object)
    );
  });

  it('fetches JSON when sorting changes', async () => {
    vi.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ meta: { filters: {} }, payload: [] }),
    });
    const wrapper = mountComponent();

    wrapper.findComponent(ToolLogsTable).vm.$emit('update:sort', {
      sort: 'account_name',
      direction: 'asc',
    });
    await flushPromises();

    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining('sort=account_name'),
      expect.any(Object)
    );
  });
});
