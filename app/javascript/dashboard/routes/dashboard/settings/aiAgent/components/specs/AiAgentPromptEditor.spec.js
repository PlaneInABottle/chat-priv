import { mount } from '@vue/test-utils';
import AiAgentPromptEditor from '../AiAgentPromptEditor.vue';

const mountComponent = props => mount(AiAgentPromptEditor, {
  props: { modelValue: '', message: 'Help', messageType: 'info', maxLength: 4000, ...props },
  global: {
    directives: {
      dompurifyHtml: (el, binding) => { el.innerHTML = binding.value; },
    },
  },
});

describe('AiAgentPromptEditor', () => {
  it('wraps selected text with bold markdown', async () => {
    const wrapper = mountComponent({ modelValue: 'hello' });
    const textarea = wrapper.find('textarea').element;
    textarea.setSelectionRange(0, 5);

    await wrapper.find('button').trigger('click');

    expect(wrapper.emitted('update:modelValue')[0][0]).toBe('**hello**');
  });

  it('inserts list markdown placeholders', async () => {
    const wrapper = mountComponent();

    await wrapper.findAll('button').find(button => button.text() === 'Bullets').trigger('click');

    expect(wrapper.emitted('update:modelValue')[0][0]).toBe('- List item');
  });

  it('renders sanitized markdown preview with raw HTML disabled by formatter', async () => {
    const wrapper = mountComponent({ modelValue: '**bold** <script>alert(1)</script>' });

    await wrapper.findAll('button').find(button => button.text() === 'Show preview').trigger('click');

    expect(wrapper.html()).toContain('<strong>bold</strong>');
    expect(wrapper.find('.prose').html()).not.toContain('<script>');
  });
});
