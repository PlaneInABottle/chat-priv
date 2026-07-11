import { flushPromises, shallowMount } from '@vue/test-utils';

import Index from '../Index.vue';

const mocks = vi.hoisted(() => ({
  get: vi.fn(),
  complete: vi.fn(),
  push: vi.fn(),
  commit: vi.fn(),
  alert: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: mocks.push }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.alert,
  useTrack: vi.fn(),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: { value: 1 },
    currentAccount: {
      value: {
        name: 'Example',
        locale: 'en',
        custom_attributes: { onboarding_step: 'ai_assistant' },
      },
    },
  }),
}));

vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({
    enabledLanguages: [{ iso_639_1_code: 'en', name: 'English' }],
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({
    value: { name: 'Owner', email: 'owner@example.com' },
  }),
  useStore: () => ({ commit: mocks.commit }),
}));

vi.mock('dashboard/api/aiAgentOnboarding', () => ({
  default: {
    get: mocks.get,
    create: vi.fn(),
    complete: mocks.complete,
  },
}));

describe('AI assistant onboarding', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.get.mockResolvedValue({
      data: {
        status: 'running',
        stage: 'crawling',
        ai_agent: { id: 42 },
        website_import: { id: 7 },
      },
    });
    mocks.complete.mockResolvedValue({ data: { ai_agent_id: 42 } });
  });

  it('lets the customer review the starter draft while analysis continues', async () => {
    const wrapper = shallowMount(Index);
    await flushPromises();

    const reviewButton = wrapper.get(
      'button[label="ONBOARDING_NEXT.BUILDING.REVIEW_STARTER"]'
    );
    await reviewButton.trigger('click');
    await flushPromises();

    expect(mocks.complete).toHaveBeenCalledOnce();
    expect(mocks.commit).toHaveBeenCalledWith('RESET_ONBOARDING', 1);
    expect(mocks.push).toHaveBeenCalledWith({
      name: 'ai_agent_instructions',
      params: { id: 42, accountId: 1 },
    });
  });
});
