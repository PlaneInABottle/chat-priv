import { mount } from '@vue/test-utils';
import AiAgentUsageSummary from '../AiAgentUsageSummary.vue';

const translations = {
  'AI_AGENT.USAGE_REPORT.TITLE': 'AI usage',
  'AI_AGENT.USAGE_REPORT.HELP':
    'Monthly AI conversation usage for this account.',
  'AI_AGENT.USAGE_REPORT.EXHAUSTED_HELP':
    'AI replies are paused until the monthly limit resets. New customer messages are routed to humans.',
  'AI_AGENT.USAGE_REPORT.REMAINING': '{count} left',
  'AI_AGENT.USAGE_REPORT.USED_OF_LIMIT': '{used} of {limit} used',
  'AI_AGENT.USAGE_REPORT.RESET_AT': 'Resets',
  'AI_AGENT.USAGE_REPORT.REUSE_WINDOW': 'Same customer window',
  'AI_AGENT.USAGE_REPORT.HOURS': '{count} hours',
  'AI_AGENT.USAGE_REPORT.AI_REPLIES': 'AI replies',
  'AI_AGENT.USAGE_REPORT.HANDOFFS': 'Handoffs',
  'AI_AGENT.USAGE_REPORT.COUNTED_CONVERSATIONS':
    '{count} counted conversations',
  'AI_AGENT.USAGE_REPORT.TOOL_CALLS': '{count} tool calls',
  'AI_AGENT.USAGE_REPORT.RECENT_CONVERSATIONS':
    'Recent counted conversations',
  'AI_AGENT.USAGE_REPORT.UNKNOWN_CONTACT': 'Unknown contact',
  'AI_AGENT.USAGE_REPORT.CONVERSATION_LABEL': 'Conversation #{id}',
  'AI_AGENT.USAGE_REPORT.COUNTED_AT': 'Counted {time}',
  'AI_AGENT.USAGE_REPORT.REUSE_UNTIL': 'Reuse until {time}',
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

const mountComponent = usage =>
  mount(AiAgentUsageSummary, {
    props: { usage },
    global: {
      stubs: {
        Icon: { template: '<i />' },
      },
    },
  });

describe('AiAgentUsageSummary', () => {
  it('renders remaining usage and reset metadata', () => {
    const wrapper = mountComponent({
      limit: 10,
      used: 3,
      remaining: 7,
      unlimited: false,
      status: 'ok',
      reset_at: '2026-07-01T00:00:00Z',
      reuse_window_hours: 24,
      metrics: {
        counted_conversations: 3,
        ai_replies: 8,
        tool_calls: 4,
        handoffs: 1,
      },
      recent_events: [
        {
          id: 7,
          conversation_display_id: 42,
          contact_name: 'Jane Customer',
          created_at: '2026-06-05T12:00:00Z',
          window_ends_at: '2026-06-06T12:00:00Z',
        },
      ],
    });

    expect(wrapper.text()).toContain('7 left');
    expect(wrapper.text()).toContain('3 of 10 used');
    expect(wrapper.text()).toContain('24 hours');
    expect(wrapper.text()).toContain('8');
    expect(wrapper.text()).toContain('1');
    expect(wrapper.text()).toContain('Recent counted conversations');
    expect(wrapper.text()).toContain('Jane Customer');
    expect(wrapper.text()).toContain('Conversation #42');
  });

  it('renders exhausted help text when usage is exhausted', () => {
    const wrapper = mountComponent({
      limit: 1,
      used: 1,
      remaining: 0,
      unlimited: false,
      status: 'exhausted',
      reset_at: '2026-07-01T00:00:00Z',
      reuse_window_hours: 24,
      metrics: {},
    });

    expect(wrapper.text()).toContain('AI replies are paused');
    expect(wrapper.text()).toContain('0 left');
  });
});
