import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import ReportMetricCard from 'dashboard/routes/dashboard/settings/reports/components/ReportMetricCard.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mountComponent = (props = {}) =>
  mount(ReportMetricCard, { props });

describe('ReportMetricCard.vue', () => {
  it('renders label and value', async () => {
    const wrapper = await mountComponent({
      label: 'Total Conversations',
      value: '1,234',
      infoText: 'Total count of conversations',
    });
    expect(wrapper.text()).toContain('Total Conversations');
    expect(wrapper.text()).toContain('1,234');
  });

  it('renders info icon with tooltip', async () => {
    const wrapper = await mountComponent({
      label: 'Test',
      value: '0',
      infoText: 'Help text',
    });
    const infoIcon = wrapper.find('[data-test-id="reportMetricInfo"]');
    expect(infoIcon.exists()).toBe(true);
  });

  it('applies disabled styling when disabled', async () => {
    const wrapper = await mountComponent({
      label: 'Test',
      value: '0',
      infoText: 'Help',
      disabled: true,
    });
    const container = wrapper.find('[data-test-id="reportMetricContainer"]');
    expect(container.classes()).toContain('grayscale');
    expect(container.classes()).toContain('opacity-30');
  });

  it('uses Lucide icon (i-lucide-info) instead of fluent-icon', async () => {
    const wrapper = await mountComponent({
      label: 'Test',
      value: '0',
      infoText: 'Help',
    });
    expect(wrapper.html()).toContain('i-lucide-info');
    expect(wrapper.html()).not.toContain('fluent-icon');
  });
});
