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
    global: {
      directives: {
        dompurifyHtml: (element, binding) => {
          element.innerHTML = binding.value;
        },
      },
    },
  });
};

const findSendButton = wrapper => wrapper.findComponent(Button);

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

  it('labels chat controls and can hide the mobile back action', async () => {
    const wrapper = mountComponent();

    expect(findSendButton(wrapper).attributes('aria-label')).toBe(
      'AI_AGENT.TEST_CONVERSATIONS.SEND'
    );
    expect(wrapper.get('input').attributes()).toMatchObject({
      name: 'test-message',
      autocomplete: 'off',
    });
    expect(
      wrapper
        .get('[data-testid="test-conversation-back"]')
        .attributes('aria-label')
    ).toBe('AI_AGENT.BACK');

    await wrapper.setProps({ showBackButton: false });

    expect(
      wrapper.find('[data-testid="test-conversation-back"]').exists()
    ).toBe(false);
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

  it('renders clickable option previews and emits the grounded selection', async () => {
    const wrapper = mountComponent({
      conversation: {
        ...conversation,
        messages: [
          {
            id: 'options-1',
            role: 'assistant',
            content: 'Nasıl devam edelim?',
            terminal_action: 'present_options',
            tool_result: {
              presentation: {
                content_type: 'input_select',
                items: [
                  { title: 'Ürün seçimi', value: 'products' },
                  { title: 'Sipariş desteği', value: 'orders' },
                ],
              },
            },
          },
        ],
        messages_count: 1,
      },
    });

    const options = wrapper
      .findAll('button')
      .filter(button =>
        ['Ürün seçimi', 'Sipariş desteği'].includes(button.text())
      );
    expect(options).toHaveLength(2);
    await options[1].trigger('click');

    expect(wrapper.emitted('send')).toEqual([
      [
        {
          content: 'Sipariş desteği',
          replyToMessageId: 'options-1',
          selectedValue: 'orders',
        },
      ],
    ]);
  });

  it('disables a persisted option preview after it has been answered', () => {
    const wrapper = mountComponent({
      conversation: {
        ...conversation,
        messages: [
          {
            id: 'options-1',
            role: 'assistant',
            content: 'Choose',
            terminal_action: 'present_options',
            submitted_values: [{ title: 'Sales', value: 'sales' }],
            tool_result: {
              presentation: {
                content_type: 'input_select',
                items: [{ title: 'Sales', value: 'sales' }],
              },
            },
          },
        ],
        messages_count: 1,
      },
    });

    expect(
      wrapper
        .findAll('button')
        .find(button => button.text() === 'Sales')
        .attributes('disabled')
    ).toBeDefined();
  });

  it('disables an option preview superseded by a newer customer message', async () => {
    const wrapper = mountComponent({
      conversation: {
        ...conversation,
        messages: [
          {
            id: 'options-1',
            role: 'assistant',
            content: 'Choose',
            terminal_action: 'present_options',
            tool_result: {
              presentation: {
                content_type: 'input_select',
                items: [{ title: 'Window products', value: 'windows' }],
              },
            },
          },
          {
            id: 'customer-2',
            role: 'user',
            content: 'Actually I need a grey balcony door option',
          },
        ],
        messages_count: 2,
      },
    });

    const staleOption = wrapper
      .findAll('button')
      .find(button => button.text() === 'Window products');
    expect(staleOption.attributes('disabled')).toBeDefined();

    await staleOption.trigger('click');
    expect(wrapper.emitted('send')).toBeUndefined();
  });

  it('renders compact source attributions below assistant answers', () => {
    const wrapper = mountComponent({
      conversation: {
        ...conversation,
        messages: [
          {
            id: 'answer-1',
            role: 'assistant',
            content:
              'Custom products can be reviewed for return within 14 days.',
            source_attributions: [
              { source_id: 4, source_name: 'Returns and exchanges' },
              { source_id: 7, source_name: 'Custom order policy' },
            ],
          },
        ],
        messages_count: 1,
      },
    });

    expect(wrapper.text()).toContain(
      'AI_AGENT.TEST_CONVERSATIONS.SOURCES_USED'
    );
    expect(wrapper.text()).toContain('Returns and exchanges');
    expect(wrapper.text()).toContain('Custom order policy');
  });

  it('renders assistant markdown using the shared message formatter', () => {
    const wrapper = mountComponent({
      conversation: {
        ...conversation,
        messages: [
          {
            id: 'answer-markdown',
            role: 'assistant',
            content:
              '**Recommended**\n\n- First option\n- [Product page](https://example.com/product)',
          },
        ],
        messages_count: 1,
      },
    });

    const content = wrapper.get('[data-testid="assistant-message-content"]');
    expect(content.get('strong').text()).toBe('Recommended');
    expect(content.findAll('li').map(item => item.text())).toEqual([
      'First option',
      'Product page',
    ]);
    expect(content.get('a').attributes()).toMatchObject({
      href: 'https://example.com/product',
      target: '_blank',
      rel: 'noreferrer noopener nofollow',
    });
  });
});
