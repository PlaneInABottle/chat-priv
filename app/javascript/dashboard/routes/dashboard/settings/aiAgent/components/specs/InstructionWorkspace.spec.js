import { shallowMount } from '@vue/test-utils';

import InstructionWorkspace from '../InstructionWorkspace.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${params.count}` : key),
  }),
}));

const instructions = {
  version: 3,
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
            'enabledMenuOptions',
            'placeholder',
          ],
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
});
