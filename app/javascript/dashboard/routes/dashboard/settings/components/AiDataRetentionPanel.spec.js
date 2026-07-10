import { flushPromises, shallowMount } from '@vue/test-utils';

import AiDataRetentionAPI from 'dashboard/api/aiDataRetention';
import AiDataRetentionPanel from './AiDataRetentionPanel.vue';

vi.mock('dashboard/api/aiDataRetention', () => ({
  default: {
    get: vi.fn(),
    updatePolicy: vi.fn(),
    purge: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
  }),
}));

const policyPayload = {
  text: { days: 30 },
  voice: { days: 90 },
  allowed_days: [7, 30, 90, 180, 365],
};

const mountComponent = async (kind = 'text') => {
  AiDataRetentionAPI.get.mockResolvedValue({ data: policyPayload });
  const wrapper = shallowMount(AiDataRetentionPanel, {
    props: { kind },
    global: {
      stubs: {
        Button: true,
        Dialog: true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('AiDataRetentionPanel', () => {
  it('loads the policy for its separate AI mode', async () => {
    const wrapper = await mountComponent('voice');

    expect(AiDataRetentionAPI.get).toHaveBeenCalled();
    expect(wrapper.vm.days).toBe(90);
    expect(wrapper.vm.allowedDays).toEqual([7, 30, 90, 180, 365]);
  });

  it('saves and queues cleanup for the selected mode', async () => {
    const wrapper = await mountComponent('text');
    AiDataRetentionAPI.updatePolicy.mockResolvedValue({
      data: { ...policyPayload, text: { days: 90 } },
    });
    AiDataRetentionAPI.purge.mockResolvedValue({ data: { status: 'queued' } });

    wrapper.vm.days = 90;
    await wrapper.vm.savePolicy();
    await wrapper.vm.queueCleanup();

    expect(AiDataRetentionAPI.updatePolicy).toHaveBeenCalledWith('text', 90);
    expect(AiDataRetentionAPI.purge).toHaveBeenCalledWith('text');
    expect(wrapper.vm.savedDays).toBe(90);
  });
});
