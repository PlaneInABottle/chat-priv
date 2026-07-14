import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';

import Index from '../Index.vue';

const mocks = vi.hoisted(() => ({
  create: vi.fn(),
  push: vi.fn(),
  commit: vi.fn(),
  alert: vi.fn(),
}));

const activeLocale = ref('en');

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: activeLocale }),
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
        locale: 'tr',
        custom_attributes: { onboarding_step: 'account_details' },
      },
    },
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({
    value: { name: 'Owner', email: 'owner@example.com' },
  }),
  useStore: () => ({ commit: mocks.commit }),
}));

vi.mock('dashboard/api/aiAgentOnboarding', () => ({
  default: { create: mocks.create },
}));

const mountComponent = () =>
  mount(Index, {
    global: {
      stubs: {
        Avatar: true,
        Icon: true,
        Spinner: true,
        OnboardingLayout: {
          template: '<div><slot /></div>',
          props: [
            'greeting',
            'subtitle',
            'continueLabel',
            'isLoading',
            'disabled',
          ],
        },
        OnboardingSection: { template: '<section><slot /></section>' },
        OnboardingFormRow: { template: '<div><slot /></div>' },
        OnboardingFormSelect: {
          template: '<select />',
          props: ['modelValue', 'options', 'placeholder', 'hasError'],
        },
      },
    },
  });

describe('AI assistant onboarding', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    activeLocale.value = 'en';
    mocks.create.mockResolvedValue({ data: { ai_agent: { id: 42 } } });
  });

  it('defaults to Turkish and keeps the website directly editable', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.vm.locale).toBe('tr');
    expect(activeLocale.value).toBe('tr');
    expect(
      wrapper.get('input[name="website"]').attributes('readonly')
    ).toBeUndefined();
  });

  it('switches the onboarding interface when English is selected', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    wrapper.vm.locale = 'en';
    await wrapper.vm.$nextTick();

    expect(activeLocale.value).toBe('en');
  });

  it('routes directly to the instruction editor after creating the draft', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    wrapper.vm.website = 'example.com';
    await wrapper.vm.handleSubmit();
    await flushPromises();

    expect(mocks.create).toHaveBeenCalledWith(
      expect.objectContaining({
        account: expect.objectContaining({
          locale: 'tr',
          website: 'example.com',
        }),
      })
    );
    expect(mocks.commit).toHaveBeenCalledWith('RESET_ONBOARDING', 1);
    expect(mocks.push).toHaveBeenCalledWith({
      name: 'ai_agent_instructions',
      params: { id: 42, accountId: 1 },
    });
  });

  it('shows invalid website feedback next to the editable field', async () => {
    mocks.create.mockRejectedValue({
      response: { data: { code: 'invalid_website' } },
    });
    const wrapper = mountComponent();
    await flushPromises();

    wrapper.vm.website = 'not a website';
    await wrapper.vm.handleSubmit();
    await flushPromises();

    expect(wrapper.vm.websiteError).toBe('ONBOARDING_NEXT.WEBSITE_ERROR');
    expect(wrapper.text()).toContain('ONBOARDING_NEXT.WEBSITE_ERROR');
  });
});
