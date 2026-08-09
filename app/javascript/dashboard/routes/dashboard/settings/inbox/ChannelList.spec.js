import { shallowMount } from '@vue/test-utils';
import ChannelList from './ChannelList.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { apiChannelName: 'API Sandbox' } }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: { value: 1 },
    currentAccount: { value: { features: { channel_voice: true } } },
  }),
}));

describe('ChannelList', () => {
  it('keeps API and voice inbox creation paths available', () => {
    window.kozmopathConfig = {};
    const wrapper = shallowMount(ChannelList);
    const channels = wrapper.findAllComponents({ name: 'ChannelItem' });
    const keys = channels.map(item => item.props('channel').key);

    expect(keys).toEqual(
      expect.arrayContaining(['api', 'voice', 'whatsapp_call'])
    );
    expect(
      channels
        .find(item => item.props('channel').key === 'api')
        .props('channel').title
    ).toBe('API Sandbox');
  });
});
