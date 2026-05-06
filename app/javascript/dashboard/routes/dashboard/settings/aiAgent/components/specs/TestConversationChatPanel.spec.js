import { mount } from '@vue/test-utils';
import Button from 'dashboard/components-next/button/Button.vue';
import TestConversationChatPanel from '../TestConversationChatPanel.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const conversation = {
  id: 1,
  title: 'Test conversation',
  messages: [],
  messages_count: 0,
};

const mountComponent = (props = {}) => {
  return mount(TestConversationChatPanel, {
    props: {
      conversation,
      uiFlags: { isSending: false },
      isDisabled: false,
      ...props,
    },
  });
};

const findSendButton = wrapper => wrapper.findAll('button')[1];

describe('TestConversationChatPanel.vue', () => {
  it('renders the send button as a non-submit button and emits trimmed send content on click', async () => {
    const wrapper = mountComponent();

    await wrapper.find('input').setValue('  Hello world  ');

    const sendButton = findSendButton(wrapper);

    expect(sendButton.attributes('type')).toBe('button');

    await sendButton.trigger('click');

    expect(wrapper.emitted('send')).toEqual([['Hello world']]);
    expect(wrapper.find('input').element.value).toBe('');
  });

  it('does not emit send when the input is blank or disabled', async () => {
    const wrapper = mountComponent();

    await wrapper.find('input').setValue('   ');
    await findSendButton(wrapper).trigger('click');

    expect(wrapper.emitted('send')).toBeUndefined();

    await wrapper.setProps({ isDisabled: true });
    await wrapper.find('input').setValue('Hello again');
    await findSendButton(wrapper).trigger('click');

    expect(wrapper.emitted('send')).toBeUndefined();
  });

  it('uses a supported button size for the send action', () => {
    const wrapper = mountComponent();

    expect(wrapper.findComponent(Button).props('size')).toBe('sm');
  });
});
