import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import MessageContextMenu from './MessageContextMenu.vue';
import MessageApi from 'dashboard/api/inbox/message';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/api/inbox/message', () => ({
  default: {
    suggestLearning: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: () => vi.fn(),
}));

const mountComponent = () => {
  const store = createStore({
    getters: {
      'accounts/getAccount': () => () => ({ locale: 'en' }),
      getCurrentAccountId: () => 51,
      getUISettings: () => ({ locale: 'en' }),
      'accounts/isFeatureEnabledonAccount': () => () => true,
    },
  });

  return mount(MessageContextMenu, {
    props: {
      message: {
        id: 44,
        conversation_id: 12,
        content: 'Delivery timing depends on the destination.',
        content_attributes: {},
      },
      isOpen: true,
      enabledOptions: { learning: true },
      contextMenuPosition: { x: 20, y: 20 },
    },
    global: {
      plugins: [store],
      mocks: { $t: key => key },
      stubs: {
        ContextMenu: { template: '<div><slot /></div>' },
        MenuItem: {
          template:
            '<button @click="$emit(\'click\', $event)">{{ option.label }}</button>',
          props: ['option'],
          emits: ['click'],
        },
        NextButton: true,
        AddCannedModal: true,
        WootDeleteModal: true,
      },
    },
  });
};

describe('MessageContextMenu.vue AI learning action', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    MessageApi.suggestLearning.mockResolvedValue({
      data: { status: 'pending' },
    });
  });

  it('sends the human reply for review without changing the assistant', async () => {
    const wrapper = mountComponent();
    const action = wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('CONVERSATION.CONTEXT_MENU.AI_LEARNING.ACTION')
      );

    await action.trigger('click');
    await flushPromises();

    expect(MessageApi.suggestLearning).toHaveBeenCalledWith(12, 44);
    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.CONTEXT_MENU.AI_LEARNING.SUGGESTED'
    );
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('reports when the reply was already applied', async () => {
    MessageApi.suggestLearning.mockResolvedValue({
      data: { status: 'applied' },
    });
    const wrapper = mountComponent();
    const action = wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('CONVERSATION.CONTEXT_MENU.AI_LEARNING.ACTION')
      );

    await action.trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.CONTEXT_MENU.AI_LEARNING.ALREADY_APPLIED'
    );
  });
});
