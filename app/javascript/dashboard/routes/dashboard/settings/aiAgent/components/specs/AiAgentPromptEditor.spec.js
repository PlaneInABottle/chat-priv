import { mount } from '@vue/test-utils';
import AiAgentPromptEditor from '../AiAgentPromptEditor.vue';

const mountComponent = props =>
  mount(AiAgentPromptEditor, {
    props: {
      modelValue: '**hello**',
      message: 'Help',
      messageType: 'info',
      maxLength: 4000,
      ...props,
    },
    global: { mocks: { $t: key => key } },
  });

describe('AiAgentPromptEditor', () => {
  it('renders instructions as plain text with an explicit limit', () => {
    const wrapper = mountComponent();
    const textarea = wrapper.find('textarea');

    expect(textarea.element.value).toBe('**hello**');
    expect(textarea.attributes('maxlength')).toBe('4000');
    expect(wrapper.text()).toContain('9 / 4000');
    expect(wrapper.text()).toContain('Help');
  });

  it('emits plain-text model updates from the textarea', async () => {
    const wrapper = mountComponent();

    await wrapper.find('textarea').setValue('Updated instructions');

    expect(wrapper.emitted('update:modelValue')[0][0]).toBe(
      'Updated instructions'
    );
  });

  it('disables editing when requested', () => {
    const wrapper = mountComponent({ disabled: true });

    expect(wrapper.find('textarea').attributes('disabled')).toBeDefined();
  });
});
