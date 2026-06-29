import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

import Badge from './Badge.vue';

describe('Badge.vue', () => {
  it('renders nothing when count is 0', () => {
    const wrapper = mount(Badge, { props: { count: 0 } });
    expect(wrapper.find('.rounded-full').exists()).toBe(false);
  });

  it('renders the count when > 0', () => {
    const wrapper = mount(Badge, { props: { count: 5 } });
    expect(wrapper.text()).toBe('5');
  });

  it('shows overflow when count exceeds threshold', () => {
    const wrapper = mount(Badge, {
      props: { count: 150, overflowThreshold: 99 },
    });
    expect(wrapper.text()).toBe('99+');
  });

  it('applies teal variant classes', () => {
    const wrapper = mount(Badge, {
      props: { count: 3, variant: 'teal' },
    });
    const badge = wrapper.find('.rounded-full');
    expect(badge.classes()).toContain('bg-n-teal-9');
    expect(badge.classes()).toContain('text-white');
  });

  it('applies slate variant classes', () => {
    const wrapper = mount(Badge, {
      props: { count: 3, variant: 'slate' },
    });
    const badge = wrapper.find('.rounded-full');
    expect(badge.classes()).toContain('bg-n-slate-4');
  });

  it('applies alert variant classes', () => {
    const wrapper = mount(Badge, {
      props: { count: 3, variant: 'alert' },
    });
    const badge = wrapper.find('.rounded-full');
    expect(badge.classes()).toContain('bg-n-ruby-9');
  });

  it('applies sm size classes', () => {
    const wrapper = mount(Badge, {
      props: { count: 3, size: 'sm' },
    });
    const badge = wrapper.find('.rounded-full');
    expect(badge.classes()).toContain('h-4');
    expect(badge.classes()).toContain('min-w-4');
  });

  it('applies md size classes', () => {
    const wrapper = mount(Badge, {
      props: { count: 3, size: 'md' },
    });
    const badge = wrapper.find('.rounded-full');
    expect(badge.classes()).toContain('h-5');
    expect(badge.classes()).toContain('min-w-5');
  });

  it('handles string count input', () => {
    const wrapper = mount(Badge, { props: { count: '7' } });
    expect(wrapper.text()).toBe('7');
  });
});
