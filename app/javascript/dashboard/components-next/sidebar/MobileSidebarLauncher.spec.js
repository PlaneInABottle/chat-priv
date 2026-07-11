import { mount } from '@vue/test-utils';

import MobileSidebarLauncher from './MobileSidebarLauncher.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'settings_account' }),
}));

describe('MobileSidebarLauncher.vue', () => {
  it('labels the icon action for both sidebar states', async () => {
    const wrapper = mount(MobileSidebarLauncher);

    expect(wrapper.get('button').attributes('aria-label')).toBe(
      'Open navigation'
    );

    await wrapper.setProps({ isMobileSidebarOpen: true });

    expect(wrapper.get('button').attributes('aria-label')).toBe(
      'Close navigation'
    );
  });

  it('emits toggle from the launcher button', async () => {
    const wrapper = mount(MobileSidebarLauncher);

    await wrapper.get('button').trigger('click');

    expect(wrapper.emitted('toggle')).toHaveLength(1);
  });
});
