import { mount } from '@vue/test-utils';
import AiAgentPromptEditor from '../AiAgentPromptEditor.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';

vi.mock('dashboard/components-next/Editor/Editor.vue', () => ({
  default: {
    name: 'Editor',
    props: {
      modelValue: { type: String, default: '' },
      editorKey: { type: String, default: '' },
      label: { type: String, default: '' },
      placeholder: { type: String, default: '' },
      message: { type: String, default: '' },
      messageType: { type: String, default: 'info' },
      maxLength: { type: Number, default: 4000 },
      showCharacterCount: { type: Boolean, default: false },
      enableCannedResponses: { type: Boolean, default: true },
    },
    emits: ['update:modelValue'],
    template: '<div data-test-id="wysiwyg-editor" />',
  },
}));

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
  it('renders the WYSIWYG editor with prompt props', () => {
    const wrapper = mountComponent();

    expect(wrapper.findComponent(Editor).props()).toMatchObject({
      modelValue: '**hello**',
      message: 'Help',
      messageType: 'info',
      maxLength: 4000,
      showCharacterCount: true,
      enableCannedResponses: false,
    });
  });

  it('emits markdown model updates from the editor', async () => {
    const wrapper = mountComponent();

    await wrapper.findComponent(Editor).vm.$emit('update:modelValue', '*updated*');

    expect(wrapper.emitted('update:modelValue')[0][0]).toBe('*updated*');
  });

  it('does not render preview controls or a textarea', () => {
    const wrapper = mountComponent();

    expect(wrapper.text()).not.toContain('Show preview');
    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(wrapper.find('.prose').exists()).toBe(false);
  });
});
