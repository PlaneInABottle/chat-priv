import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';
import SkeletonCard from './SkeletonCard.vue';

describe('SkeletonCard.vue', () => {
  it('renders the specified number of skeleton items', () => {
    const wrapper = mount(SkeletonCard, { props: { count: 3 } });
    const items = wrapper.findAll('.animate-pulse');
    expect(items).toHaveLength(3);
  });

  it('defaults to 5 items', () => {
    const wrapper = mount(SkeletonCard);
    const items = wrapper.findAll('.animate-pulse');
    expect(items).toHaveLength(5);
  });

  it('renders avatar placeholder with conversation variant size', () => {
    const wrapper = mount(SkeletonCard, {
      props: { count: 1, variant: 'conversation' },
    });
    const avatar = wrapper.find('.flex-shrink-0.rounded-full');
    expect(avatar.classes()).toContain('size-6');
  });

  it('renders larger avatar for contact variant', () => {
    const wrapper = mount(SkeletonCard, {
      props: { count: 1, variant: 'contact' },
    });
    const avatar = wrapper.find('.flex-shrink-0.rounded-full');
    expect(avatar.classes()).toContain('size-10');
  });
});
