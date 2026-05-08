import { mount } from '@vue/test-utils';
import ToolLogsTable from '../ToolLogsTable.vue';

const defaultRow = {
  id: 1,
  account_name: 'Acme',
  tool_key: 'human_handoff',
  tool_name: 'human_handoff',
  status: 'executed',
  duration_ms: 245,
  created_at: new Date().toISOString(),
  conversation_url: '/app/accounts/1/conversations/2',
  conversation_display_id: 2,
  arguments: { reason: 'Help' },
  result: { status: 'ok' },
};

const mountComponent = props => mount(ToolLogsTable, { props });

describe('ToolLogsTable', () => {
  it('renders rows without the account column by default', () => {
    const wrapper = mountComponent({ rows: [defaultRow] });

    expect(wrapper.text()).toContain('human_handoff');
    expect(wrapper.text()).toContain('245ms');
    expect(wrapper.text()).toContain('Executed');
    expect(wrapper.text()).not.toContain('Acme');
  });

  it('renders the account column when requested', () => {
    const wrapper = mountComponent({ rows: [defaultRow], showAccountColumn: true });

    expect(wrapper.text()).toContain('Account');
    expect(wrapper.text()).toContain('Acme');
  });

  it('expands JSON details', async () => {
    const wrapper = mountComponent({ rows: [defaultRow] });

    expect(wrapper.text()).not.toContain('Help');
    await wrapper.find('button[aria-label="Expand row"]').trigger('click');

    expect(wrapper.text()).toContain('Help');
    expect(wrapper.text()).toContain('Arguments');
  });

  it('emits filter updates', async () => {
    const wrapper = mountComponent({ rows: [defaultRow] });

    await wrapper.find('select').setValue('error');

    expect(wrapper.emitted('update:filters')[0][0]).toMatchObject({
      status: 'error',
    });
  });

  it('emits sort updates', async () => {
    const wrapper = mountComponent({ rows: [defaultRow] });

    await wrapper.findAll('th button')[0].trigger('click');

    expect(wrapper.emitted('update:sort')[0][0]).toEqual({
      sort: 'created_at',
      direction: 'asc',
    });
  });

  it('handles unknown tools and missing conversation or duration', () => {
    const wrapper = mountComponent({
      rows: [
        {
          ...defaultRow,
          tool_key: 'unknown_tool',
          tool_name: '',
          conversation_url: null,
          duration_ms: null,
        },
      ],
    });

    expect(wrapper.text()).toContain('unknown_tool');
    expect(wrapper.text()).toContain('—');
  });
});
