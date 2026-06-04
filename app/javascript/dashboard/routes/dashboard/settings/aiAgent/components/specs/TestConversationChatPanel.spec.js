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

  it('prevents default click navigation when sending', async () => {
    const wrapper = mountComponent();
    const preventDefault = vi.fn();
    const stopPropagation = vi.fn();

    await wrapper.find('input').setValue('Hello world');
    await findSendButton(wrapper).trigger('click', {
      preventDefault,
      stopPropagation,
    });

    expect(preventDefault).toHaveBeenCalled();
    expect(stopPropagation).toHaveBeenCalled();
    expect(wrapper.emitted('send')).toEqual([['Hello world']]);
  });

  it('uses a supported button size for the send action', () => {
    const wrapper = mountComponent();

    expect(wrapper.findComponent(Button).props('size')).toBe('sm');
  });

  it('renders human handoff preview metadata inside assistant messages', () => {
    const wrapper = mountComponent({
      conversation: {
        ...conversation,
        messages: [
          {
            id: 'handoff-1',
            role: 'assistant',
            content: 'Transferring to another agent for further assistance.',
            terminal_action: 'handoff',
            tool_result: {
              customer_message:
                'Transferring to another agent for further assistance.',
              private_note_preview: 'Escalate to billing',
              labels_to_apply: ['vip'],
              labels_ignored: ['ignored'],
            },
          },
        ],
        messages_count: 1,
      },
    });

    expect(wrapper.text()).toContain(
      'AI_AGENT.TEST_CONVERSATIONS.HANDOFF_TITLE'
    );
    expect(wrapper.text()).toContain('Escalate to billing');
    expect(wrapper.text()).toContain('vip');
    expect(wrapper.text()).toContain('ignored');
  });

  it('renders ikas tool call metadata inside assistant messages', () => {
    const wrapper = mountComponent({
      conversation: {
        ...conversation,
        messages: [
          {
            id: 'catalog-1',
            role: 'assistant',
            content: '70x100 ölçünüze uygun ürünler var.',
            tool_events: [
              {
                tool: 'ikas_catalog_search',
                status: 'ok',
                tool_call_id: 'call_1',
                args: { query: 'akordiyon sineklik 70x100' },
                result: { result_type: 'show_compatible_candidates' },
              },
            ],
          },
        ],
        messages_count: 1,
      },
    });

    expect(wrapper.text()).toContain('AI_AGENT.TEST_CONVERSATIONS.TOOL_CALLS');
    expect(wrapper.text()).toContain('ikas_catalog_search');
    expect(wrapper.text()).toContain('akordiyon sineklik 70x100');
    expect(wrapper.text()).toContain('show_compatible_candidates');
  });
});
