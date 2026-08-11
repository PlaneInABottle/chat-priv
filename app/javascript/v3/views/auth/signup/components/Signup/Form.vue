<script setup>
import { ref, computed, reactive } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, email } from '@vuelidate/validators';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import VueHcaptcha from '@hcaptcha/vue3-hcaptcha';
import FormInput from '../../../../../components/Form/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PasswordRequirements from './PasswordRequirements.vue';
import { isValidPassword } from 'shared/helpers/Validators';
import GoogleOAuthButton from '../../../../../components/GoogleOauth/Button.vue';
import { register } from '../../../../../api/auth';
import * as CompanyEmailValidator from 'company-email-validator';

const MIN_PASSWORD_LENGTH = 6;

const store = useStore();
const { t } = useI18n();
const router = useRouter();

const hCaptcha = ref(null);
const isPasswordFocused = ref(false);
const isSignupInProgress = ref(false);

const credentials = reactive({
  email: '',
  password: '',
  hCaptchaClientResponse: '',
});

const rules = {
  credentials: {
    email: {
      required,
      email,
      businessEmailValidator(value) {
        return CompanyEmailValidator.isCompanyEmail(value);
      },
    },
    password: {
      required,
      isValidPassword,
      minLength: minLength(MIN_PASSWORD_LENGTH),
    },
  },
};

const v$ = useVuelidate(rules, { credentials });

const globalConfig = computed(() => store.getters['globalConfig/get']);

const termsLink = computed(() =>
  t('REGISTER.TERMS_ACCEPT')
    .replace(
      'https://www.kozmopath.com/terms-of-service',
      globalConfig.value.termsURL
    )
    .replace(
      'https://www.kozmopath.com/privacy-policy',
      globalConfig.value.privacyURL
    )
);

const allowedLoginMethods = computed(
  () => window.kozmopathConfig.allowedLoginMethods || ['email']
);

const showGoogleOAuth = computed(
  () =>
    allowedLoginMethods.value.includes('google_oauth') &&
    Boolean(window.kozmopathConfig.googleOAuthClientId)
);

const isFormValid = computed(() => !v$.value.$invalid);

const performRegistration = async () => {
  isSignupInProgress.value = true;
  try {
    const result = await register(credentials);
    if (result.authenticated) return;

    router.push({
      name: 'auth_verify_email',
      state: { email: credentials.email },
    });
  } catch (error) {
    const errorMessage = error?.message || t('REGISTER.API.ERROR_MESSAGE');
    if (globalConfig.value.hCaptchaSiteKey) {
      hCaptcha.value.reset();
      credentials.hCaptchaClientResponse = '';
    }
    useAlert(errorMessage);
  } finally {
    isSignupInProgress.value = false;
  }
};

const submit = () => {
  if (isSignupInProgress.value) return;
  v$.value.$touch();
  if (v$.value.$invalid) return;
  isSignupInProgress.value = true;
  if (globalConfig.value.hCaptchaSiteKey) {
    hCaptcha.value.execute();
  } else {
    performRegistration();
  }
};

const onRecaptchaVerified = token => {
  credentials.hCaptchaClientResponse = token;
  performRegistration();
};

const onCaptchaError = () => {
  isSignupInProgress.value = false;
  credentials.hCaptchaClientResponse = '';
  hCaptcha.value.reset();
};
</script>

<template>
  <div class="flex-1">
    <form
      data-testid="freemium-signup-form"
      class="grid gap-4"
      @submit.prevent="submit"
    >
      <FormInput
        id="email_address"
        v-model="credentials.email"
        type="email"
        name="email_address"
        :class="{ error: v$.credentials.email.$error }"
        :label="$t('REGISTER.EMAIL.LABEL')"
        :placeholder="$t('REGISTER.EMAIL.PLACEHOLDER')"
        :has-error="v$.credentials.email.$error"
        :error-message="$t('REGISTER.EMAIL.ERROR')"
        class="bg-white text-[#10211f] outline-[#10211f]/20 placeholder:text-[#65726e] focus:outline-[#5471e5]"
        @blur="v$.credentials.email.$touch"
      />
      <div class="relative">
        <FormInput
          id="password"
          v-model="credentials.password"
          type="password"
          name="password"
          :class="{ error: v$.credentials.password.$error }"
          :label="$t('REGISTER.PASSWORD.LABEL')"
          :placeholder="$t('REGISTER.PASSWORD.PLACEHOLDER')"
          :has-error="v$.credentials.password.$error"
          class="bg-white text-[#10211f] outline-[#10211f]/20 placeholder:text-[#65726e] focus:outline-[#5471e5]"
          @focus="isPasswordFocused = true"
          @blur="
            isPasswordFocused = false;
            v$.credentials.password.$touch();
          "
        />
        <Transition
          enter-active-class="transition duration-200 ease-out origin-left"
          enter-from-class="opacity-0 scale-90 translate-x-1"
          enter-to-class="opacity-100 scale-100 translate-x-0"
          leave-active-class="transition duration-150 ease-in origin-left"
          leave-from-class="opacity-100 scale-100 translate-x-0"
          leave-to-class="opacity-0 scale-90 translate-x-1"
        >
          <PasswordRequirements
            v-if="isPasswordFocused"
            :password="credentials.password"
            class="max-sm:static max-sm:mt-2"
          />
        </Transition>
      </div>
      <VueHcaptcha
        v-if="globalConfig.hCaptchaSiteKey"
        ref="hCaptcha"
        size="invisible"
        :sitekey="globalConfig.hCaptchaSiteKey"
        @verify="onRecaptchaVerified"
        @error="onCaptchaError"
        @expired="onCaptchaError"
        @challenge-expired="onCaptchaError"
        @closed="onCaptchaError"
      />
      <NextButton
        lg
        type="submit"
        data-testid="submit_button"
        class="w-full font-medium"
        :label="$t('REGISTER.FREEMIUM.SUBMIT')"
        :disabled="isSignupInProgress || !isFormValid"
        :is-loading="isSignupInProgress"
      />
    </form>
    <GoogleOAuthButton v-if="showGoogleOAuth" class="mt-3 w-full">
      {{ $t('REGISTER.OAUTH.GOOGLE_SIGNUP') }}
    </GoogleOAuthButton>
    <p
      class="mb-0 mt-4 text-sm leading-relaxed text-[#63716c] [&>a]:font-semibold [&>a]:text-[#304ebd] [&>a]:underline [&>a]:underline-offset-2 hover:[&>a]:text-[#233d9c]"
      v-html="termsLink"
    />
  </div>
</template>
