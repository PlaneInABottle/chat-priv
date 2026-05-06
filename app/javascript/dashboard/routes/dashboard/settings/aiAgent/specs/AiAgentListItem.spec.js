import { mount } from '@vue/test-utils';
import AiAgentListItem from '../AiAgentListItem.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) => {
      if (key === 'AI_AGENTS.ITEM.INBOXES_COUNT') {
        return `${values.count} inboxes`;
      }

      return key;
    },
  }),
}));

const buildAgent = overrides => ({
  id: 1,
  name: 'Helper',
  enabled: true,
  created_at: '2026-01-01T00:00:00.000Z',
  agent_bot: { inbox_ids: [] },
  ...overrides,
});

const mountComponent = agent =>
  mount(AiAgentListItem, {
    props: {
      agent,
    },
    global: {
      stubs: {
        Button: {
          template: '<button>{{ label }}</button>',
          props: ['label'],
        },
        RouterLink: {
          template: '<a><slot /></a>',
        },
      },
    },
  });

describe('AiAgentListItem.vue', () => {
  it('renders inbox count from agent_bot inbox bindings', () => {
    const wrapper = mountComponent(
      buildAgent({ agent_bot: { inbox_ids: [3, 5] } })
    );

    expect(wrapper.text()).toContain('2 inboxes');
  });
});
