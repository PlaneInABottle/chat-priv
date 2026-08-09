import { shallowMount } from '@vue/test-utils';
import FeatureSpotlight from './FeatureSpotlight.vue';

describe('FeatureSpotlight', () => {
  const mountComponent = learnMoreUrl =>
    shallowMount(FeatureSpotlight, {
      props: { learnMoreUrl },
      global: { mocks: { $t: key => key } },
    });

  it('does not render the learn-more action for Chatwoot help URLs', () => {
    const wrapper = mountComponent('https://chwt.app/captain-faq');

    expect(wrapper.findAll('button-stub')).toHaveLength(0);
  });

  it('renders the learn-more action for a custom help URL', () => {
    const wrapper = mountComponent('https://docs.example.com/captain-faq');

    expect(wrapper.findAll('button-stub')).toHaveLength(1);
  });
});
