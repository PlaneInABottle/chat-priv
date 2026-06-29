import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';

import ConversationCard from 'dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue';

const pushMock = vi.fn();

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: pushMock }),
  useRoute: () => ({ params: { accountId: 1 } }),
}));

vi.mock('shared/helpers/timeHelper', () => ({
  dynamicTime: vi.fn(() => 'now'),
  shortTimestamp: vi.fn(() => 'now'),
}));

vi.mock('dashboard/helper/URLHelper.js', () => ({
  frontendURL: path => `/app/accounts/1${path}`,
  conversationUrl: ({ id }) => `/inbox/${id}`,
}));

vi.mock('dashboard/helper/inbox', () => ({
  getInboxIconByType: () => 'i-lucide-message-circle',
}));

const buildConversation = overrides => ({
  id: 99,
  timestamp: '2026-01-01T00:00:00.000Z',
  labels: [],
  ...overrides,
});

const buildContact = () => ({
  name: 'Jane Doe',
  thumbnail: '',
  availabilityStatus: 'online',
});

const buildInbox = () => ({
  channelType: 'Channel::WebWidget',
  medium: 'web',
  name: 'Support',
});

const mountComponent = ({ conversation, contact, inbox } = {}) =>
  mount(ConversationCard, {
    props: {
      conversation: conversation || buildConversation(),
      contact: contact || buildContact(),
      stateInbox: inbox || buildInbox(),
      accountLabels: [],
    },
    global: {
      stubs: {
        Icon: true,
        Avatar: true,
        CardMessagePreview: true,
        CardMessagePreviewWithMeta: true,
        CardPriorityIcon: true,
      },
    },
  });

describe('ConversationCard.vue', () => {
  beforeEach(() => {
    pushMock.mockClear();
    window.chatwootConfig = { hostURL: 'http://localhost:3000' };
  });

  it('navigates via router.push on click', async () => {
    const wrapper = await mountComponent();
    const card = wrapper.find('[role="button"]');
    await card.trigger('click');

    expect(pushMock).toHaveBeenCalledWith({ path: '/app/accounts/1/inbox/99' });
  });

  it('is keyboard focusable with tabindex=0', async () => {
    const wrapper = await mountComponent();
    const card = wrapper.find('[role="button"]');
    expect(card.attributes('tabindex')).toBe('0');
  });

  it('navigates on Enter keydown', async () => {
    const wrapper = await mountComponent();
    const card = wrapper.find('[role="button"]');
    await card.trigger('keydown.enter');

    expect(pushMock).toHaveBeenCalledWith({ path: '/app/accounts/1/inbox/99' });
  });

  it('navigates on Space keydown', async () => {
    const wrapper = await mountComponent();
    const card = wrapper.find('[role="button"]');
    await card.trigger('keydown.space');

    expect(pushMock).toHaveBeenCalledWith({ path: '/app/accounts/1/inbox/99' });
  });

  it('opens new tab on meta+click without calling router.push', async () => {
    const openMock = vi.spyOn(window, 'open').mockImplementation(() => {});
    const wrapper = await mountComponent();
    const card = wrapper.find('[role="button"]');
    await card.trigger('click', { metaKey: true });

    expect(openMock).toHaveBeenCalled();
    expect(pushMock).not.toHaveBeenCalled();
    openMock.mockRestore();
  });
});
