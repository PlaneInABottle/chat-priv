import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';

import DraftTestPanel from '../DraftTestPanel.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const instructions = {
  version: 3,
  profile: {
    language: 'not_set',
    tone: 'not_set',
    formality: 'not_set',
    response_length: 'not_set',
  },
  sections: { additional: 'Help customers.' },
};

const mountComponent = isDraft => {
  const store = createStore({
    getters: {
      'aiAgentTestConversations/getTestConversations': () => [
        { id: 7, title: 'Test' },
      ],
      'aiAgentTestConversations/getActiveTestConversation': () => ({
        id: 7,
        title: 'Test',
      }),
      'aiAgentTestConversations/getUIFlags': () => ({}),
    },
    actions: {
      'aiAgentTestConversations/show': vi.fn(),
      'aiAgentTestConversations/create': vi.fn(),
      'aiAgentTestConversations/sendMessage': vi.fn(),
    },
  });
  const dispatch = vi.spyOn(store, 'dispatch');
  const wrapper = shallowMount(DraftTestPanel, {
    props: {
      aiAgentId: 42,
      draftInstructions: instructions,
      isDraft,
    },
    global: {
      plugins: [store],
      stubs: { TestConversationChatPanel: true, Button: true },
    },
  });

  return { wrapper, dispatch };
};

describe('DraftTestPanel', () => {
  it('tests the exact saved prompt when the document is unchanged', async () => {
    const { wrapper, dispatch } = mountComponent(false);

    await wrapper.vm.sendMessage('Hello');

    expect(dispatch).toHaveBeenCalledWith(
      'aiAgentTestConversations/sendMessage',
      expect.objectContaining({
        content: 'Hello',
        draftInstructions: undefined,
      })
    );
  });

  it('sends the current document when testing an unsaved draft', async () => {
    const { wrapper, dispatch } = mountComponent(true);

    await wrapper.vm.sendMessage('Hello');

    expect(dispatch).toHaveBeenCalledWith(
      'aiAgentTestConversations/sendMessage',
      expect.objectContaining({ draftInstructions: instructions })
    );
  });

  it('keeps saved test conversations accessible when credits are exhausted', async () => {
    const { wrapper, dispatch } = mountComponent(true);
    wrapper
      .findComponent({ name: 'ImprovementCreditsSummary' })
      .vm.$emit('loaded', { status: 'exhausted' });
    await wrapper.vm.$nextTick();

    await wrapper.vm.sendMessage('Hello');
    wrapper.vm.selectConversation(7);

    expect(dispatch).not.toHaveBeenCalledWith(
      'aiAgentTestConversations/sendMessage',
      expect.anything()
    );
    expect(dispatch).toHaveBeenCalledWith('aiAgentTestConversations/show', {
      aiAgentId: 42,
      id: 7,
    });
  });
});
