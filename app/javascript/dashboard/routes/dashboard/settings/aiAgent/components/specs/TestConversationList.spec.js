import { mount } from '@vue/test-utils';

import TestConversationList from '../TestConversationList.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const ButtonStub = {
  name: 'Button',
  props: ['label', 'icon', 'isLoading', 'disabled'],
  emits: ['click'],
  template: `
    <button :disabled="disabled" @click="$emit('click')">
      {{ label || icon }}
    </button>
  `,
};

const mountComponent = props =>
  mount(TestConversationList, {
    props: {
      conversations: [{ id: 1, title: 'Conversation 1', messages_count: 0 }],
      activeId: 1,
      uiFlags: {},
      ...props,
    },
    global: {
      stubs: {
        Button: ButtonStub,
        Dialog: { template: '<div />' },
        TestConversationListItem: { template: '<div />' },
        TestConversationEmptyState: { template: '<div />' },
      },
    },
  });

describe('TestConversationList.vue', () => {
  it('uses the clear-all loading flag for the clear-all button state', () => {
    const wrapper = mountComponent({
      uiFlags: {
        isCreating: false,
        isDeleting: false,
        isClearing: true,
      },
    });

    const [, clearAllButton] = wrapper.findAllComponents(ButtonStub);

    expect(clearAllButton.props('isLoading')).toBe(true);
    expect(clearAllButton.props('disabled')).toBe(true);
  });
});
