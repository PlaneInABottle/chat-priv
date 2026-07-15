import { flushPromises, shallowMount } from '@vue/test-utils';
import { reactive, nextTick } from 'vue';

import App from './App.vue';

const mocks = vi.hoisted(() => ({
  store: null,
  uiSettings: null,
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({}),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => mocks.store,
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: 1 }),
}));

vi.mock('dashboard/composables/useFontSize', () => ({
  useFontSize: () => ({ currentFontSize: 16 }),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: mocks.uiSettings }),
}));

vi.mock('dashboard/helper/actionCable', () => ({
  default: { init: vi.fn() },
}));

vi.mock('dashboard/helper/pushHelper', () => ({
  registerSubscription: vi.fn(),
  verifyServiceWorkerExistence: vi.fn(),
}));

vi.mock('dashboard/helper/ReconnectService', () => ({
  default: vi.fn(() => ({ disconnect: vi.fn() })),
}));

vi.mock('v3/helpers/RouteHelper', () => ({
  isOnOnboardingView: () => false,
}));

const mountComponent = ({ accountLocale = 'en', userLocale } = {}) => {
  const accounts = reactive([{ id: 1, locale: accountLocale }]);
  const i18n = reactive({ locale: 'en' });
  mocks.uiSettings = reactive({ locale: userLocale });
  mocks.store = {
    getters: {
      'accounts/getAccount': id =>
        accounts.find(account => account.id === Number(id)) || {},
      'accounts/isRTL': false,
      getCurrentUser: {},
      getAuthUIFlags: { isFetching: false },
    },
    dispatch: vi.fn().mockResolvedValue(),
  };
  window.kozmopathConfig = { selectedLocale: 'en' };
  window.matchMedia = vi.fn().mockReturnValue({ matches: false });

  const wrapper = shallowMount(App, {
    global: {
      mocks: {
        $store: mocks.store,
        $i18n: i18n,
        $route: {},
        $t: key => key,
      },
      stubs: { RouterView: true },
    },
  });

  return { accounts, i18n, wrapper };
};

describe('App dashboard locale', () => {
  it('reacts when onboarding changes the account default locale', async () => {
    const { accounts, i18n } = mountComponent();
    await flushPromises();

    accounts[0].locale = 'tr';
    await nextTick();

    expect(i18n.locale).toBe('tr');
  });

  it('keeps an explicit user locale when the account default changes', async () => {
    const { accounts, i18n } = mountComponent({ userLocale: 'en' });
    await flushPromises();

    accounts[0].locale = 'tr';
    await nextTick();

    expect(i18n.locale).toBe('en');
  });
});
