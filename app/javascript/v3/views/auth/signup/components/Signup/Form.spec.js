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
  props: ['modelValue', 'name', 'type'],
  emits: ['update:modelValue'],
  template: `
    <input
      :name="name"
      :type="type"
      :value="modelValue"
      @input="$emit('update:modelValue', $event.target.value)"
    />
  `,
};

const NextButtonStub = {
  props: ['disabled', 'label'],
  template: '<button type="submit" :disabled="disabled">{{ label }}</button>',
};

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
    const wrapper = shallowMount(SignupForm, {
      global: {
        stubs: {
          FormInput: FormInputStub,
          NextButton: NextButtonStub,
          GoogleOAuthButton: true,
          PasswordRequirements: true,
          VueHcaptcha: true,
        },
      },
    });

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
    const wrapper = shallowMount(SignupForm, {
      global: {
        stubs: {
          FormInput: FormInputStub,
          NextButton: NextButtonStub,
          GoogleOAuthButton: true,
          PasswordRequirements: true,
          VueHcaptcha: true,
        },
      },
    });

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
});
