import { mount } from '@vue/test-utils';

import Icon from './Icon.vue';

describe('Icon.vue', () => {
  it('preserves caller classes, styles, and aria attributes', () => {
    const wrapper = mount(Icon, {
      props: { icon: 'info' },
      attrs: {
        class: 'size-4 text-n-slate-11',
        style: 'color: rgb(10, 20, 30);',
        'aria-label': 'More information',
      },
    });

    const icon = wrapper.find('span');

    expect(icon.classes()).toEqual(
      expect.arrayContaining(['i-lucide-info', 'size-4', 'text-n-slate-11'])
    );
    expect(icon.attributes('style')).toContain('color: rgb(10, 20, 30)');
    expect(icon.attributes('aria-label')).toBe('More information');
    expect(icon.attributes('aria-hidden')).toBeUndefined();
  });

  it('keeps decorative icons hidden from assistive technology by default', () => {
    const wrapper = mount(Icon, {
      props: { icon: 'checkmark', size: 16 },
    });

    const icon = wrapper.find('span');

    expect(icon.classes()).toContain('i-lucide-check');
    expect(icon.attributes('aria-hidden')).toBe('true');
    expect(icon.attributes('style')).toContain('width: 16px');
  });
});
