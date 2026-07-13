import { mount } from '@vue/test-utils';

import ResponsiveTabNavigation from './ResponsiveTabNavigation.vue';

const tabs = [
  { label: 'Instructions', value: 'instructions' },
  { label: 'Knowledge', value: 'knowledge' },
];

describe('ResponsiveTabNavigation', () => {
  it('emits the selected tab from the compact menu', async () => {
    const wrapper = mount(ResponsiveTabNavigation, {
      props: {
        tabs,
        activeTabIndex: 0,
        ariaLabel: 'Assistant view',
      },
    });

    await wrapper.get('select').setValue('1');

    expect(wrapper.emitted('tabChanged')).toEqual([[tabs[1]]]);
  });
});
