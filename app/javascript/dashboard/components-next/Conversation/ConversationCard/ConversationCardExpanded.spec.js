import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';

import ConversationCardExpanded from './ConversationCardExpanded.vue';

const chat = {
  id: 99,
  labels: [],
  messages: [],
  priority: null,
  status: 'open',
  unread_count: 0,
  timestamp: '2026-01-01T00:00:00.000Z',
  created_at: '2026-01-01T00:00:00.000Z',
};

const currentContact = {
  name: 'Jane Doe',
  thumbnail: '',
};

const mountComponent = () =>
  mount(ConversationCardExpanded, {
    props: {
      chat,
      currentContact,
    },
    global: {
      stubs: {
        Avatar: true,
        CardAvatar: true,
        CardContent: true,
        CardLabels: true,
        CardPriorityIcon: true,
        CardStatusIcon: true,
        Checkbox: true,
        Icon: true,
        InboxName: true,
        SLACardLabel: true,
        TimeAgo: true,
      },
    },
  });

describe('ConversationCardExpanded', () => {
  it('is keyboard operable as an interactive row', async () => {
    const wrapper = mountComponent();
    const row = wrapper.find('[role="button"]');

    expect(row.attributes('tabindex')).toBe('0');

    await row.trigger('keydown.enter');
    await row.trigger('keydown.space');

    expect(wrapper.emitted('click')).toHaveLength(2);
  });
});
