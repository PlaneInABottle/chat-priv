import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import { nextTick } from 'vue';

import TabBar from './TabBar.vue';

const tabs = [
  { label: 'Overview' },
  { label: 'Settings' },
  { label: 'Activity' },
];

describe('TabBar', () => {
  it('moves focus and emits tab changes with arrow keys', async () => {
    const wrapper = mount(TabBar, {
      attachTo: document.body,
      props: {
        tabs,
        initialActiveTab: 0,
      },
    });
    const tabButtons = wrapper.findAll('[role="tab"]');

    expect(tabButtons.map(tab => tab.attributes('tabindex'))).toEqual([
      '0',
      '-1',
      '-1',
    ]);

    await tabButtons[0].trigger('keydown', { key: 'ArrowRight' });
    await nextTick();

    expect(wrapper.emitted('tabChanged')?.[0]).toEqual([tabs[1]]);
    expect(document.activeElement).toBe(tabButtons[1].element);

    wrapper.unmount();
  });
});
