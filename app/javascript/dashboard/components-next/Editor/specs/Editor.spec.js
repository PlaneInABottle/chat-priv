import { shallowMount } from '@vue/test-utils';

import Editor from '../Editor.vue';

describe('Editor', () => {
  it('passes an accessible name to the article editor', () => {
    const wrapper = shallowMount(Editor, {
      props: {
        modelValue: 'Instruction text',
        variant: 'article',
        ariaLabel: 'Rules and boundaries',
      },
    });

    expect(
      wrapper.findComponent({ name: 'FullEditor' }).props('ariaLabel')
    ).toBe('Rules and boundaries');
  });

  it('keeps explicit CSS height values unchanged', () => {
    const wrapper = shallowMount(Editor, {
      props: {
        modelValue: 'Instruction text',
        variant: 'article',
        minHeight: '10rem',
        maxHeight: '28rem',
      },
    });

    expect(wrapper.find('.editor-wrapper').attributes('style')).toContain(
      '--editor-field-min-height: 10rem'
    );
    expect(wrapper.find('.editor-wrapper').attributes('style')).toContain(
      '--editor-field-max-height: 28rem'
    );
  });
});
