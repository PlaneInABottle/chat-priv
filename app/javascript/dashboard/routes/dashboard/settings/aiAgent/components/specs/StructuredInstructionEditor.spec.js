import { shallowMount } from '@vue/test-utils';

import StructuredInstructionEditor from '../StructuredInstructionEditor.vue';

const modelValue = {
  locale: 'en',
  profile: { language: 'en' },
  sections: { custom_guidance: 'Original' },
};

const descriptors = [
  {
    key: 'overview',
    type: 'preview',
    shortTitle: 'All',
    title: 'All',
    description: 'Preview',
  },
  {
    key: 'preferences',
    type: 'profile',
    shortTitle: 'Profile',
    title: 'Profile',
    description: 'Preferences',
  },
  {
    key: 'custom_guidance',
    type: 'section',
    shortTitle: 'Custom',
    title: 'Custom guidance',
    description: 'Arbitrary section',
    placeholder: 'Write guidance',
  },
];

const mountComponent = () =>
  shallowMount(StructuredInstructionEditor, {
    props: {
      modelValue,
      descriptors,
      profileFields: [{ key: 'language', label: 'Language' }],
      profileOptions: { language: [['en', 'English']] },
      compiledInstructions: 'Compiled',
      contentLength: 8,
      editorKeyPrefix: 'shared',
      countLabel: '8 / 50000',
      emptyPreviewLabel: 'Empty',
      selectorLabel: 'Section',
    },
    global: {
      directives: { dompurifyHtml: () => {} },
      stubs: {
        Editor: {
          name: 'Editor',
          template: '<div />',
          props: ['modelValue', 'editorKey', 'placeholder'],
        },
      },
    },
  });

describe('StructuredInstructionEditor', () => {
  it('bounds and scrolls only the compiled preview content', async () => {
    const wrapper = mountComponent();
    await wrapper
      .findComponent({ name: 'InstructionSectionNavigator' })
      .vm.$emit('select', 'overview');
    const preview = wrapper.get('[data-testid="all-instructions-content"]');

    expect(preview.classes()).toEqual(
      expect.arrayContaining([
        'max-h-[32rem]',
        'overflow-x-hidden',
        'overflow-y-auto',
        'overscroll-contain',
      ])
    );
    expect(preview.attributes()).toMatchObject({
      'aria-label': 'All',
      tabindex: '0',
    });

    await wrapper
      .findComponent({ name: 'InstructionSectionNavigator' })
      .vm.$emit('select', 'custom_guidance');
    const section = wrapper.get('[data-testid="instruction-section-content"]');
    expect(section.classes()).not.toContain('max-h-[32rem]');
    expect(section.classes()).not.toContain('overflow-x-hidden');
    expect(section.classes()).not.toContain('overscroll-contain');
  });

  it('renders and updates arbitrary descriptor keys without product modes', async () => {
    const wrapper = mountComponent();
    await wrapper
      .findComponent({ name: 'InstructionSectionNavigator' })
      .vm.$emit('select', 'custom_guidance');

    const editor = wrapper.findComponent({ name: 'Editor' });
    expect(editor.props()).toMatchObject({
      modelValue: 'Original',
      editorKey: 'shared-custom_guidance',
      placeholder: 'Write guidance',
    });

    await editor.vm.$emit('update:modelValue', 'Updated');
    expect(wrapper.emitted('update:modelValue').at(-1)[0].sections).toEqual({
      custom_guidance: 'Updated',
    });
  });
});
