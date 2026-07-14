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
const currentAccount = ref({
  name: 'Example',
  locale: 'tr',
  custom_attributes: { onboarding_step: 'account_details' },
});

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
    locale: activeLocale,
  }),
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
    currentAccount,
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
        Transition: {
          template: '<div><slot /></div>',
        },
        NextButton: {
          props: [
            'type',
            'label',
            'disabled',
            'isLoading',
            'icon',
            'variant',
            'color',
          ],
          emits: ['click'],
          template:
            '<button :type="type" :disabled="disabled" @click="$emit(\'click\')">{{ label }}<slot /></button>',
        },
      },
    },
  });

const clickPrimary = async wrapper => {
  await wrapper.get('form').trigger('submit');
  await flushPromises();
};

describe('AI assistant onboarding', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    activeLocale.value = 'en';
    currentAccount.value = {
      name: 'Example',
      locale: 'tr',
      custom_attributes: { onboarding_step: 'account_details' },
    };
    mocks.create.mockResolvedValue({ data: { ai_agent: { id: 42 } } });
  });

  it('asks for language first instead of showing the full questionnaire', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.vm.currentStep).toBe('language');
    expect(wrapper.find('input[name="website"]').exists()).toBe(false);
    expect(wrapper.find('[role="progressbar"]').exists()).toBe(true);
    expect(wrapper.vm.locale).toBe('tr');
    expect(activeLocale.value).toBe('tr');

    await clickPrimary(wrapper);

    expect(wrapper.vm.currentStep).toBe('website');
    expect(wrapper.get('input[name="website"]').attributes('readonly')).toBe(
      undefined
    );
  });

  it('shows one decision at a time and preserves answers when going back', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await clickPrimary(wrapper);
    await wrapper.get('input[name="website"]').setValue('example.com');
    await clickPrimary(wrapper);

    expect(wrapper.vm.currentStep).toBe('tone');
    expect(wrapper.find('input[name="website"]').exists()).toBe(false);
    await wrapper.get('[data-testid="onboarding-back"]').trigger('click');
    await flushPromises();

    expect(wrapper.vm.currentStep).toBe('website');
    expect(wrapper.vm.website).toBe('example.com');
  });

  it('switches the whole onboarding interface from the first language choice', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.get('input[name="language"][value="en"]').setValue();

    expect(wrapper.vm.locale).toBe('en');
    expect(activeLocale.value).toBe('en');
  });

  it('reviews choices and lets the customer jump back to edit one', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.vm.goToStep('website');
    wrapper.vm.website = 'example.com';
    wrapper.vm.aiTone = 'professional';
    await wrapper.vm.goToStep('review');
    await flushPromises();

    expect(wrapper.text()).toContain('example.com');
    expect(wrapper.text()).toContain(
      'ONBOARDING_NEXT.TONE.OPTIONS.PROFESSIONAL.TITLE'
    );
    expect(
      wrapper
        .findAll('button')
        .filter(button => button.text().includes('ONBOARDING_NEXT.REVIEW.EDIT'))
    ).toHaveLength(3);

    const [websiteEdit] = wrapper
      .findAll('button')
      .filter(button => button.text().includes('ONBOARDING_NEXT.REVIEW.EDIT'));
    await websiteEdit.trigger('click');
    await flushPromises();

    expect(wrapper.vm.currentStep).toBe('website');
    expect(wrapper.get('input[name="website"]').element.value).toBe(
      'example.com'
    );
  });

  it('creates the draft only from review and omits retired questionnaire answers', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    wrapper.vm.website = 'example.com';
    wrapper.vm.aiTone = 'concise';
    await wrapper.vm.goToStep('review');
    await clickPrimary(wrapper);

    expect(mocks.create).toHaveBeenCalledWith({
      account: expect.objectContaining({
        locale: 'tr',
        website: 'example.com',
      }),
      assistant: {
        tone: 'concise',
      },
    });
    const request = mocks.create.mock.calls[0][0];
    expect(request.account).not.toHaveProperty('user_role');
    expect(request.account).not.toHaveProperty('referral_source');
    expect(mocks.commit).toHaveBeenCalledWith('RESET_ONBOARDING', 1);
    expect(mocks.push).toHaveBeenCalledWith({
      name: 'ai_agent_instructions',
      params: { id: 42, accountId: 1 },
    });
  });

  it('returns directly to review after changing the language from review', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.vm.goToStep('review');
    await flushPromises();
    const editButtons = wrapper
      .findAll('button')
      .filter(button => button.text().includes('ONBOARDING_NEXT.REVIEW.EDIT'));
    await editButtons.at(-1).trigger('click');
    await flushPromises();

    expect(wrapper.vm.currentStep).toBe('language');
    await wrapper.get('input[name="language"][value="en"]').setValue();
    await clickPrimary(wrapper);

    expect(wrapper.vm.currentStep).toBe('review');
    expect(wrapper.vm.locale).toBe('en');
  });

  it('returns to the website step when the website cannot be validated', async () => {
    mocks.create.mockRejectedValue({
      response: { data: { code: 'invalid_website' } },
    });
    const wrapper = mountComponent();
    await flushPromises();

    wrapper.vm.website = 'not a website';
    await wrapper.vm.goToStep('review');
    await clickPrimary(wrapper);

    expect(wrapper.vm.currentStep).toBe('website');
    expect(wrapper.vm.websiteError).toBe('ONBOARDING_NEXT.WEBSITE_ERROR');
    expect(wrapper.text()).toContain('ONBOARDING_NEXT.WEBSITE_ERROR');
  });

  it('allows setup to progress while optional account enrichment runs', async () => {
    currentAccount.value = {
      name: 'Example',
      locale: 'tr',
      custom_attributes: { onboarding_step: 'enrichment' },
    };
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.vm.isEnriching).toBe(true);
    await clickPrimary(wrapper);

    expect(wrapper.vm.currentStep).toBe('website');
    expect(wrapper.text()).toContain('ONBOARDING_NEXT.WEBSITE.ENRICHING');
    expect(
      wrapper.get('[data-testid="onboarding-primary"]').attributes('disabled')
    ).toBeUndefined();
  });
});
