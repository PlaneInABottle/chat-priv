import { flushPromises, mount } from '@vue/test-utils';
import { nextTick } from 'vue';

import AiSetup from './AiSetup.vue';

const accountState = vi.hoisted(() => ({ accountId: null }));
const textMocks = vi.hoisted(() => ({ get: vi.fn() }));
const voiceMocks = vi.hoisted(() => ({
  getAgents: vi.fn(),
}));

vi.mock('dashboard/api/aiAgent', () => ({
  default: textMocks,
}));

vi.mock('dashboard/api/voice', () => ({
  default: voiceMocks,
}));

vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  accountState.accountId = ref(1);
  return {
    useAccount: () => ({ accountId: accountState.accountId }),
  };
});

vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: () => computed(() => () => true),
  };
});

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRouter: () => ({ push: vi.fn() }),
}));

const deferred = () => {
  let resolve;
  const promise = new Promise(resolvePromise => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
};

const setupAgent = (id, name) => ({
  id,
  name,
  lifecycle_status: 'draft',
  readiness: { checks: [] },
});

const mountComponent = () =>
  mount(AiSetup, {
    global: {
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
          props: ['isLoading'],
        },
        BaseSettingsHeader: { template: '<div />' },
        Button: { template: '<button>{{ label }}</button>', props: ['label'] },
        Icon: { template: '<i />' },
      },
    },
  });

describe('AiSetup.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    accountState.accountId.value = 1;
    textMocks.get.mockResolvedValue({ data: [] });
  });

  it('ignores late setup responses from the previous account', async () => {
    const firstTextResponse = deferred();
    const secondTextResponse = deferred();
    const firstResponse = deferred();
    const secondResponse = deferred();
    textMocks.get
      .mockReturnValueOnce(firstTextResponse.promise)
      .mockReturnValueOnce(secondTextResponse.promise);
    voiceMocks.getAgents
      .mockReturnValueOnce(firstResponse.promise)
      .mockReturnValueOnce(secondResponse.promise);

    const wrapper = mountComponent();
    await nextTick();
    expect(voiceMocks.getAgents).toHaveBeenCalledTimes(1);

    accountState.accountId.value = 2;
    await nextTick();
    expect(voiceMocks.getAgents).toHaveBeenCalledTimes(2);

    secondResponse.resolve({
      data: { payload: [setupAgent(2, 'Second account voice assistant')] },
    });
    secondTextResponse.resolve({
      data: [setupAgent(4, 'Second account text assistant')],
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Second account voice assistant');
    expect(wrapper.text()).toContain('Second account text assistant');

    firstResponse.resolve({
      data: { payload: [setupAgent(1, 'First account voice assistant')] },
    });
    firstTextResponse.resolve({
      data: [setupAgent(3, 'First account text assistant')],
    });
    await flushPromises();

    expect(wrapper.text()).toContain('Second account voice assistant');
    expect(wrapper.text()).toContain('Second account text assistant');
    expect(wrapper.text()).not.toContain('First account voice assistant');
    expect(wrapper.text()).not.toContain('First account text assistant');
  });
});
