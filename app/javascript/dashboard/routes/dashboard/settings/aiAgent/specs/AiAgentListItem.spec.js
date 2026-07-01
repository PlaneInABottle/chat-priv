import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import AiAgentListItem from '../AiAgentListItem.vue';

const pushMock = vi.fn();

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

vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: pushMock,
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
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
          props: ['label'],
          emits: ['click'],
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

  it('navigates to detail page via router.push instead of router-link', async () => {
    const wrapper = mountComponent(buildAgent({ id: 42 }));
    pushMock.mockClear();

    const buttons = wrapper.findAll('button');
    const editButton = buttons.find(b => b.text() === 'AI_AGENTS.ITEM.EDIT');
    await editButton.trigger('click');

    expect(pushMock).toHaveBeenCalledWith({
      name: 'ai_agent_detail',
      params: { id: 42 },
    });
  });

  it('emits delete event when delete button is clicked', async () => {
    const wrapper = mountComponent(buildAgent({ id: 7 }));
    pushMock.mockClear();

    const buttons = wrapper.findAll('button');
    const deleteButton = buttons.find(
      b => b.text() === 'AI_AGENTS.ITEM.DELETE'
    );
    await deleteButton.trigger('click');

    expect(pushMock).not.toHaveBeenCalled();
    expect(wrapper.emitted('delete')).toBeTruthy();
    expect(wrapper.emitted('delete')[0][0].id).toBe(7);
  });

  it('renders enabled status badge when agent is enabled', () => {
    const wrapper = mountComponent(buildAgent({ enabled: true }));
    expect(wrapper.text()).toContain('AI_AGENTS.ITEM.STATUS_ENABLED');
  });

  it('renders disabled status badge when agent is disabled', () => {
    const wrapper = mountComponent(buildAgent({ enabled: false }));
    expect(wrapper.text()).toContain('AI_AGENTS.ITEM.STATUS_DISABLED');
  });
});
