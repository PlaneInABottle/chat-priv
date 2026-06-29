import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { useMapGetter } from 'dashboard/composables/store';
import SidebarNotificationBell from 'dashboard/components-next/sidebar/SidebarNotificationBell.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'dashboard' }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

const mountComponent = (unreadCount = 0) => {
  useMapGetter.mockReturnValue({ value: { unreadCount } });
  return mount(SidebarNotificationBell, {
    global: {
      stubs: {},
    },
  });
};

describe('SidebarNotificationBell.vue', () => {
  it('renders an accessible aria-label on the button', async () => {
    const wrapper = await mountComponent(3);
    const button = wrapper.find('button');
    expect(button.attributes('aria-label')).toBeTruthy();
  });

  it('includes unread count in aria-label when present', async () => {
    const wrapper = await mountComponent(5);
    const label = wrapper.find('button').attributes('aria-label');
    expect(label).toContain('5');
  });

  it('shows 99+ when unread exceeds 99', async () => {
    const wrapper = await mountComponent(150);
    expect(wrapper.text()).toContain('99+');
  });

  it('does not show a badge when unreadCount is 0', async () => {
    const wrapper = await mountComponent(0);
    const badges = wrapper.findAll('.bg-n-ruby-9');
    expect(badges).toHaveLength(0);
  });
});
