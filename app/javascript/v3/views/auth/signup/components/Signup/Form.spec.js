import { flushPromises, shallowMount } from '@vue/test-utils';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { register } from '../../../../../api/auth';
import SignupForm from './Form.vue';

vi.mock('vue-i18n');
vi.mock('vue-router');
vi.mock('vuex');
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../../../../../api/auth', () => ({ register: vi.fn() }));

const FormInputStub = {
  props: ['modelValue', 'id', 'name', 'type', 'label'],
  emits: ['update:modelValue'],
  template: `
    <label :for="id">
      {{ label }}
      <input
        :name="name"
        :id="id"
        :type="type"
        :value="modelValue"
        @input="$emit('update:modelValue', $event.target.value)"
      />
    </label>
  `,
};

const NextButtonStub = {
  props: ['disabled', 'label'],
  template: '<button type="submit" :disabled="disabled">{{ label }}</button>',
};

const mountForm = (stubs = {}) =>
  shallowMount(SignupForm, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        FormInput: FormInputStub,
        NextButton: NextButtonStub,
        GoogleOAuthButton: {
          template: '<button data-testid="google-oauth"><slot /></button>',
        },
        PasswordRequirements: {
          template: '<div data-testid="password-requirements" />',
        },
        VueHcaptcha: {
          template: '<div data-testid="hcaptcha" />',
        },
        ...stubs,
      },
    },
  });

describe('Signup Form', () => {
  const router = { push: vi.fn() };

  beforeEach(() => {
    useStore.mockReturnValue({
      getters: {
        'globalConfig/get': {
          hCaptchaSiteKey: '',
          privacyURL: 'https://www.kozmopath.com/privacy-policy',
          termsURL: 'https://www.kozmopath.com/terms-of-service',
        },
      },
    });
    useI18n.mockReturnValue({ t: vi.fn(key => key) });
    useRouter.mockReturnValue(router);
    window.kozmopathConfig = { allowedLoginMethods: ['email'] };
  });

  afterEach(() => {
    window.kozmopathConfig = {};
  });

  it('navigates confirmation-required signups to verify email', async () => {
    register.mockResolvedValue({
      authenticated: false,
      email: 'owner@acme.com',
    });
    const wrapper = mountForm();

    await wrapper
      .find('input[name="email_address"]')
      .setValue('owner@acme.com');
    await wrapper.find('input[name="password"]').setValue('Password1!');
    await flushPromises();
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(register).toHaveBeenCalledWith(
      expect.objectContaining({
        email: 'owner@acme.com',
        password: 'Password1!',
      })
    );
    expect(router.push).toHaveBeenCalledWith({
      name: 'auth_verify_email',
      state: { email: 'owner@acme.com' },
    });
  });

  it('does not navigate to verify email after authenticated signup', async () => {
    register.mockResolvedValue({ authenticated: true });
    const wrapper = mountForm();

    await wrapper
      .find('input[name="email_address"]')
      .setValue('owner@acme.com');
    await wrapper.find('input[name="password"]').setValue('Password1!');
    await flushPromises();
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(register).toHaveBeenCalled();
    expect(router.push).not.toHaveBeenCalled();
  });

  it('uses the selected freemium presentation while preserving conditional controls and legal links', () => {
    useStore.mockReturnValue({
      getters: {
        'globalConfig/get': {
          hCaptchaSiteKey: 'test-site-key',
          privacyURL: 'https://www.kozmopath.com/privacy-policy',
          termsURL: 'https://www.kozmopath.com/terms-of-service',
        },
      },
    });
    useI18n.mockReturnValue({
      t: vi.fn(key => {
        if (key === 'REGISTER.TERMS_ACCEPT') {
          return 'Read <a href="https://www.kozmopath.com/terms-of-service">terms</a> and <a href="https://www.kozmopath.com/privacy-policy">privacy</a>';
        }
        return key;
      }),
    });
    window.kozmopathConfig = {
      allowedLoginMethods: ['email', 'google_oauth'],
      googleOAuthClientId: 'test-client-id',
    };

    const wrapper = mountForm();

    expect(wrapper.get('form').attributes('data-testid')).toBe(
      'freemium-signup-form'
    );
    expect(wrapper.get('button[type="submit"]').text()).toBe(
      'REGISTER.FREEMIUM.SUBMIT'
    );
    expect(wrapper.text()).toContain('REGISTER.EMAIL.LABEL');
    expect(wrapper.text()).toContain('REGISTER.PASSWORD.LABEL');
    expect(wrapper.get('label[for="email_address"]')).toBeTruthy();
    expect(wrapper.get('label[for="password"]')).toBeTruthy();
    expect(wrapper.get('[data-testid="hcaptcha"]')).toBeTruthy();
    expect(wrapper.get('[data-testid="google-oauth"]')).toBeTruthy();
    expect(
      wrapper.get("a[href='https://www.kozmopath.com/terms-of-service']")
    ).toBeTruthy();
    expect(
      wrapper.get("a[href='https://www.kozmopath.com/privacy-policy']")
    ).toBeTruthy();
  });

  it('keeps the scaled rem responsive class contract for form gaps, inputs, submit and terms', () => {
    const wrapper = mountForm();

    expect(wrapper.get('form').classes()).toEqual(
      expect.arrayContaining(['gap-4', 'lg:gap-5'])
    );
    expect(wrapper.get('button[type="submit"]').classes()).toContain('lg:h-14');
    expect(wrapper.get('label[for="email_address"]').classes()).toEqual(
      expect.arrayContaining(['text-base', 'sm:!text-base'])
    );
    expect(wrapper.get('p').classes()).toEqual(
      expect.arrayContaining(['text-sm', 'lg:text-base'])
    );
  });
});
