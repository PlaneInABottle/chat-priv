import { shallowMount } from '@vue/test-utils';
import ChatOptions from 'shared/components/ChatOptions.vue';
import AgentMessageBubble from '../AgentMessageBubble.vue';

const mountBubble = contentAttributes =>
  shallowMount(AgentMessageBubble, {
    props: {
      contentType: 'input_select',
      message: 'Choose one',
      messageContentAttributes: contentAttributes,
    },
    global: {
      mocks: { $t: key => key },
      directives: { 'dompurify-html': {} },
    },
  });

describe('AgentMessageBubble', () => {
  it('hides stale AI options and explains that the choice is unavailable', () => {
    const wrapper = mountBubble({
      items: [{ title: 'Sales', value: 'sales' }],
      ai_agent: { selection: { version: 1 } },
      selection_unavailable: true,
    });

    expect(wrapper.findComponent(ChatOptions).props('hideFields')).toBe(true);
    expect(wrapper.text()).toContain('COMPONENTS.OPTION_BUBBLE.UNAVAILABLE');
  });
});
