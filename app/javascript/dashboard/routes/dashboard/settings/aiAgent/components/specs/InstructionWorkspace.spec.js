import { shallowMount } from '@vue/test-utils';

import InstructionWorkspace from '../InstructionWorkspace.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${params.count}` : key),
  }),
}));

const instructions = {
  version: 4,
  locale: 'en',
  profile: {
    language: 'same_as_customer',
    tone: 'natural',
    formality: 'balanced',
    response_length: 'balanced',
  },
  sections: {
    identity: 'Represent the store.',
    business_context: '',
    tasks: '',
    rules: 'Never invent prices.',
    handoff: '',
    examples: '',
    additional: '',
  },
};

const mountComponent = () =>
  shallowMount(InstructionWorkspace, {
    props: {
      modelValue: instructions,
      aiAgentId: 42,
      isDirty: true,
    },
    global: {
      stubs: {
        Button: true,
        DraftTestPanel: true,
        Editor: {
          name: 'Editor',
          template: '<div />',
          props: [
            'modelValue',
            'editorKey',
            'ariaLabel',
            'enabledMenuOptions',
            'placeholder',
            'minHeight',
            'maxHeight',
          ],
        },
      },
      directives: {
        dompurifyHtml: (element, binding) => {
          element.innerHTML = binding.value;
        },
      },
    },
  });

describe('InstructionWorkspace', () => {
  it('uses fixed navigation and removes heading controls from section bodies', async () => {
    const wrapper = mountComponent();
    const navigator = wrapper.findComponent({
      name: 'InstructionSectionNavigator',
    });

    await navigator.vm.$emit('select', 'rules');
    const editor = wrapper.findComponent({ name: 'Editor' });

    expect(editor.props('modelValue')).toBe('Never invent prices.');
    expect(editor.props('enabledMenuOptions')).not.toContain('h2');
    expect(editor.props('enabledMenuOptions')).not.toContain('h3');
    expect(editor.props('minHeight')).toBe('10rem');
    expect(editor.props('maxHeight')).toBe(
      'clamp(10rem, calc(100dvh - 37rem), 28rem)'
    );
    expect(editor.props('ariaLabel')).toContain('RULES.TITLE');
    expect(editor.classes()).toContain('[&_.ProseMirror]:text-[0.9375rem]');
    expect(editor.classes()).toContain('[&_.ProseMirror]:leading-6');
    expect(editor.classes()).toContain('[&_.ProseMirror_p]:!text-[0.9375rem]');
    expect(editor.classes()).toContain('[&_.ProseMirror_p]:!leading-6');
    expect(
      wrapper.get('[data-testid="instruction-section-content"]').classes()
    ).toContain('overflow-y-auto');
  });

  it('shows the compiled instruction set without mounting multiple editors', async () => {
    const wrapper = mountComponent();
    const navigator = wrapper.findComponent({
      name: 'InstructionSectionNavigator',
    });

    await navigator.vm.$emit('select', 'all');

    expect(wrapper.findComponent({ name: 'Editor' }).exists()).toBe(false);
    expect(wrapper.vm.compiledInstructions).toContain(
      '## Identity and purpose\n\nRepresent the store.'
    );
    expect(wrapper.vm.compiledInstructions).toContain(
      '## Rules and boundaries\n\nNever invent prices.'
    );
    expect(
      wrapper.get('[data-testid="all-instructions-content"]').classes()
    ).not.toContain('overflow-y-auto');
    expect(wrapper.text()).toContain(
      'AI_ASSISTANT.INSTRUCTIONS.SECTIONS.ALL.TITLE'
    );
  });

  it('shows mandatory human handoff as available when no custom guidance exists', () => {
    const wrapper = mountComponent();
    const navigator = wrapper.findComponent({
      name: 'InstructionSectionNavigator',
    });
    const handoffItem = navigator
      .props('items')
      .find(item => item.key === 'handoff');

    expect(handoffItem.configured).toBe(true);
    expect(handoffItem.statusLabel).toBe(
      'AI_ASSISTANT.INSTRUCTIONS.HANDOFF_DEFAULT_STATUS'
    );
  });

  it('updates only the selected fixed section', async () => {
    const wrapper = mountComponent();
    const navigator = wrapper.findComponent({
      name: 'InstructionSectionNavigator',
    });

    await navigator.vm.$emit('select', 'rules');
    await wrapper
      .findComponent({ name: 'Editor' })
      .vm.$emit('update:modelValue', 'Always verify prices.');

    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual({
      ...instructions,
      sections: {
        ...instructions.sections,
        rules: 'Always verify prices.',
      },
    });
  });

  it('expands the test conversation without replacing the editor workflow', async () => {
    const wrapper = mountComponent();
    const testPanel = wrapper.findComponent({ name: 'DraftTestPanel' });

    expect(testPanel.classes()).toContain('min-[1360px]:top-20');
    expect(wrapper.vm.isTestFocused).toBe(false);
    await testPanel.vm.$emit('toggleFocus');

    expect(wrapper.vm.isTestFocused).toBe(true);
    expect(testPanel.props('isFocused')).toBe(true);
  });
});
