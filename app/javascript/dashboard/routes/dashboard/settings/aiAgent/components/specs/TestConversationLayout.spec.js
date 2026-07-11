import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import TestConversationLayout from '../TestConversationLayout.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const createVuexStore = () =>
  createStore({
    getters: {
      'aiAgentTestConversations/getTestConversations': () => [
        { id: 1, title: 'Conversation 1', messages: [], messages_count: 0 },
      ],
      'aiAgentTestConversations/getActiveTestConversation': () => ({
        id: 1,
        title: 'Conversation 1',
        messages: [],
        messages_count: 0,
      }),
      'aiAgentTestConversations/getUIFlags': () => ({
        isCreating: false,
        isDeleting: false,
        isSending: false,
      }),
    },
    actions: {
      'aiAgentTestConversations/create': vi.fn(),
      'aiAgentTestConversations/show': vi.fn(),
      'aiAgentTestConversations/delete': vi.fn(),
      'aiAgentTestConversations/clearAll': vi.fn(),
      'aiAgentTestConversations/sendMessage': vi.fn(),
    },
  });

const mountComponent = ({ isDisabled = false, aiAgentId = 42 } = {}) => {
  const store = createVuexStore();
  const dispatch = vi.spyOn(store, 'dispatch');
  const wrapper = shallowMount(TestConversationLayout, {
    props: { isDisabled, aiAgentId },
    global: {
      plugins: [store],
      stubs: {
        TestConversationList: true,
        TestConversationChatPanel: true,
      },
      mocks: {
        $t: key => key,
      },
    },
  });

  return { wrapper, dispatch };
};

describe('TestConversationLayout.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('does not dispatch sidebar actions while disabled', async () => {
    const { wrapper, dispatch } = mountComponent({ isDisabled: true });

    await wrapper.vm.createConversation();
    wrapper.vm.selectConversation(1);
    wrapper.vm.deleteConversation(1);
    wrapper.vm.clearAllConversations();

    expect(dispatch).not.toHaveBeenCalled();
  });

  it('dispatches actions when enabled', async () => {
    const { wrapper, dispatch } = mountComponent({ isDisabled: false });

    dispatch.mockResolvedValue(undefined);

    await wrapper.vm.createConversation();
    wrapper.vm.selectConversation(1);
    wrapper.vm.deleteConversation(1);
    wrapper.vm.clearAllConversations();
    await wrapper.vm.sendMessage('Hello');

    expect(dispatch).toHaveBeenCalledWith('aiAgentTestConversations/create', {
      aiAgentId: 42,
    });
    expect(dispatch).toHaveBeenCalledWith('aiAgentTestConversations/show', {
      aiAgentId: 42,
      id: 1,
    });
    expect(dispatch).toHaveBeenCalledWith('aiAgentTestConversations/delete', {
      aiAgentId: 42,
      id: 1,
    });
    expect(dispatch).toHaveBeenCalledWith('aiAgentTestConversations/clearAll', {
      aiAgentId: 42,
    });
    expect(dispatch).toHaveBeenCalledWith(
      'aiAgentTestConversations/sendMessage',
      {
        aiAgentId: 42,
        id: 1,
        content: 'Hello',
      }
    );
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('shows an alert when sending a message fails', async () => {
    const { wrapper, dispatch } = mountComponent({ isDisabled: false });

    dispatch.mockResolvedValueOnce({ error: 'Failed to send message' });

    await wrapper.vm.sendMessage('Hello');

    expect(useAlert).toHaveBeenCalledWith('Failed to send message');
  });

  it('keeps history available but blocks new messages when credits are exhausted', async () => {
    const { wrapper, dispatch } = mountComponent({ isDisabled: false });
    wrapper
      .findComponent({ name: 'ImprovementCreditsSummary' })
      .vm.$emit('loaded', { status: 'exhausted' });
    await wrapper.vm.$nextTick();

    await wrapper.vm.sendMessage('Hello');
    wrapper.vm.selectConversation(1);

    expect(dispatch).not.toHaveBeenCalledWith(
      'aiAgentTestConversations/sendMessage',
      expect.anything()
    );
    expect(dispatch).toHaveBeenCalledWith('aiAgentTestConversations/show', {
      aiAgentId: 42,
      id: 1,
    });
  });
});
