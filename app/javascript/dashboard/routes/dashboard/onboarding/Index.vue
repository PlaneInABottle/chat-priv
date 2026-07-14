<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert, useTrack } from 'dashboard/composables';
import { ONBOARDING_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AssistantOnboardingLayout from './AssistantOnboardingLayout.vue';
import AiAgentOnboardingAPI from 'dashboard/api/aiAgentOnboarding';
import { AI_TONE_OPTIONS } from './shared/constants';
import { normalizeWebsiteInput } from './websiteValidation';

const { t, locale: i18nLocale } = useI18n();
const router = useRouter();
const store = useStore();
const { accountId, currentAccount } = useAccount();
const currentUser = useMapGetter('getCurrentUser');

const STEPS = ['language', 'website', 'tone', 'review'];
const QUESTION_STEP_COUNT = STEPS.length;

const website = ref('');
const locale = ref('');
const industry = ref('');
const aiTone = ref('friendly');
const currentStepIndex = ref(0);
const transitionDirection = ref('forward');
const returnToReview = ref(false);
const isSubmitting = ref(false);
const isVerifyingWebsite = ref(false);
const websiteError = ref('');
const verifiedWebsite = ref(null);
const websiteInputRef = ref(null);
const stepHeadingRef = ref(null);
const enrichmentTimedOut = ref(false);
const hasEditedWebsite = ref(false);

const userName = computed(() => currentUser.value?.name || '');
const accountName = computed(() => currentAccount.value?.name || '');
const currentStep = computed(() => STEPS[currentStepIndex.value]);
const questionStep = computed(() => currentStepIndex.value + 1);
const canGoBack = computed(() => currentStepIndex.value > 0);
const transitionName = computed(() =>
  transitionDirection.value === 'backward' ? 'step-backward' : 'step-forward'
);
const isEnriching = computed(
  () =>
    !enrichmentTimedOut.value &&
    currentAccount.value?.custom_attributes?.onboarding_step === 'enrichment'
);
const companyLogo = computed(() => {
  const logos = currentAccount.value?.custom_attributes?.brand_info?.logos;
  if (!logos?.length) return '';
  const square = logos.find(logo => logo.resolution?.aspect_ratio === 1);
  return (square || logos[0])?.url || '';
});

const languageOptions = computed(() => [
  {
    value: 'tr',
    label: t('ONBOARDING_NEXT.LANGUAGES.TR'),
    description: t('ONBOARDING_NEXT.LANGUAGE.OPTIONS.TR'),
  },
  {
    value: 'en',
    label: t('ONBOARDING_NEXT.LANGUAGES.EN'),
    description: t('ONBOARDING_NEXT.LANGUAGE.OPTIONS.EN'),
  },
]);

const toneOptions = computed(() => {
  const copy = {
    friendly: {
      label: t('ONBOARDING_NEXT.TONE.OPTIONS.FRIENDLY.TITLE'),
      description: t('ONBOARDING_NEXT.TONE.OPTIONS.FRIENDLY.DESCRIPTION'),
    },
    professional: {
      label: t('ONBOARDING_NEXT.TONE.OPTIONS.PROFESSIONAL.TITLE'),
      description: t('ONBOARDING_NEXT.TONE.OPTIONS.PROFESSIONAL.DESCRIPTION'),
    },
    concise: {
      label: t('ONBOARDING_NEXT.TONE.OPTIONS.CONCISE.TITLE'),
      description: t('ONBOARDING_NEXT.TONE.OPTIONS.CONCISE.DESCRIPTION'),
    },
  };
  return AI_TONE_OPTIONS.map(option => ({
    ...option,
    ...copy[option.value],
  }));
});

const selectedToneLabel = computed(
  () =>
    toneOptions.value.find(option => option.value === aiTone.value)?.label || ''
);
const selectedLanguageLabel = computed(
  () =>
    languageOptions.value.find(option => option.value === locale.value)
      ?.label || ''
);

const primaryLabel = computed(() => {
  if (currentStep.value === 'review') {
    return t('ONBOARDING_NEXT.REVIEW.CREATE');
  }
  if (currentStep.value === 'website' && website.value.trim()) {
    return t('ONBOARDING_NEXT.WEBSITE.VERIFY');
  }
  return t('ONBOARDING_NEXT.CONTINUE');
});

const detectBestLocale = () => {
  const accountLocale = currentAccount.value?.locale;
  return ['tr', 'en'].includes(accountLocale) ? accountLocale : 'tr';
};

const populateFormFields = () => {
  const account = currentAccount.value;
  const attrs = account?.custom_attributes || {};
  const brandInfo = attrs.brand_info;

  if (!locale.value) locale.value = detectBestLocale();
  if (!hasEditedWebsite.value && !website.value) {
    website.value = attrs.website || brandInfo?.domain || '';
  }
  if (!industry.value) {
    industry.value =
      attrs.industry || brandInfo?.industries?.[0]?.industry || '';
  }
};

const focusCurrentStep = async () => {
  await nextTick();
  stepHeadingRef.value?.focus();
};

const goToStep = async step => {
  const targetIndex = STEPS.indexOf(step);
  if (targetIndex < 0 || targetIndex === currentStepIndex.value) return;

  transitionDirection.value =
    targetIndex < currentStepIndex.value ? 'backward' : 'forward';
  currentStepIndex.value = targetIndex;
  await focusCurrentStep();
};

const goForward = () => {
  if (
    returnToReview.value &&
    ['language', 'website', 'tone'].includes(currentStep.value)
  ) {
    returnToReview.value = false;
    goToStep('review');
    return;
  }

  const nextStep = STEPS[currentStepIndex.value + 1];
  if (nextStep) goToStep(nextStep);
};

const goBack = () => {
  if (returnToReview.value) {
    returnToReview.value = false;
    goToStep('review');
    return;
  }

  const previousStep = STEPS[currentStepIndex.value - 1];
  if (previousStep) goToStep(previousStep);
};

const editStep = step => {
  returnToReview.value = true;
  goToStep(step);
};

const handleWebsiteInput = () => {
  hasEditedWebsite.value = true;
  websiteError.value = '';
  verifiedWebsite.value = null;
};

const continueWithoutWebsite = () => {
  hasEditedWebsite.value = true;
  website.value = '';
  websiteError.value = '';
  verifiedWebsite.value = null;
  goForward();
};

const verifyWebsite = async () => {
  if (isVerifyingWebsite.value) return;

  websiteError.value = '';
  const normalizedUrl = normalizeWebsiteInput(website.value);

  if (normalizedUrl === '') {
    verifiedWebsite.value = null;
    goForward();
    return;
  }
  if (!normalizedUrl) {
    websiteError.value = t('ONBOARDING_NEXT.WEBSITE.INVALID');
    await nextTick();
    websiteInputRef.value?.focus();
    return;
  }
  if (verifiedWebsite.value?.website_url === normalizedUrl) {
    goForward();
    return;
  }

  isVerifyingWebsite.value = true;
  try {
    const { data } = await AiAgentOnboardingAPI.verifyWebsite({
      website_url: normalizedUrl,
    });
    if (normalizeWebsiteInput(website.value) !== normalizedUrl) return;

    website.value = data.website_url;
    verifiedWebsite.value = data;
    goForward();
  } catch (error) {
    if (normalizeWebsiteInput(website.value) !== normalizedUrl) return;

    const errorCode = error.response?.data?.code;
    websiteError.value =
      errorCode === 'invalid_website'
        ? t('ONBOARDING_NEXT.WEBSITE.INVALID')
        : t('ONBOARDING_NEXT.WEBSITE.UNREACHABLE');
    await nextTick();
    websiteInputRef.value?.focus();
  } finally {
    isVerifyingWebsite.value = false;
  }
};

const handleSubmit = async () => {
  if (isSubmitting.value) return;

  isSubmitting.value = true;
  websiteError.value = '';
  try {
    const accountAttributes = {
      locale: locale.value,
      website: website.value,
    };
    if (website.value) {
      accountAttributes.website_verification_token =
        verifiedWebsite.value?.verification_token;
    }
    if (industry.value) accountAttributes.industry = industry.value;

    const { data } = await AiAgentOnboardingAPI.create({
      account: accountAttributes,
      assistant: {
        tone: aiTone.value,
      },
    });

    useTrack(ONBOARDING_EVENTS.ACCOUNT_DETAILS_COMPLETED, {
      has_enriched_data: Boolean(
        currentAccount.value?.custom_attributes?.brand_info
      ),
      website_changed: hasEditedWebsite.value,
      tone: aiTone.value,
    });

    store.commit('RESET_ONBOARDING', accountId.value);
    try {
      await store.dispatch('accounts/get', { silent: true });
    } catch {
      // The assistant already exists, so a stale account refresh must not block navigation.
    }
    router.push({
      name: 'ai_agent_instructions',
      params: { id: data.ai_agent.id, accountId: accountId.value },
    });
  } catch (error) {
    if (
      ['invalid_website', 'website_unreachable'].includes(
        error.response?.data?.code
      )
    ) {
      websiteError.value = t('ONBOARDING_NEXT.WEBSITE.REVERIFY');
      verifiedWebsite.value = null;
      returnToReview.value = true;
      await goToStep('website');
      await nextTick();
      websiteInputRef.value?.focus();
    } else {
      useAlert(t('ONBOARDING_NEXT.ERROR'));
    }
  } finally {
    isSubmitting.value = false;
  }
};

const handlePrimaryAction = () => {
  if (currentStep.value === 'review') {
    handleSubmit();
    return;
  }
  if (currentStep.value === 'website') {
    verifyWebsite();
    return;
  }
  goForward();
};

let enrichmentTimer = null;

const startEnrichmentTimer = () => {
  if (enrichmentTimer) clearTimeout(enrichmentTimer);
  enrichmentTimer = setTimeout(() => {
    enrichmentTimedOut.value = true;
    populateFormFields();
  }, 30000);
};

onMounted(() => {
  populateFormFields();
  useTrack(ONBOARDING_EVENTS.ACCOUNT_DETAILS_VISITED);
  if (isEnriching.value) startEnrichmentTimer();
});

onUnmounted(() => {
  if (enrichmentTimer) clearTimeout(enrichmentTimer);
});

watch(isEnriching, value => {
  if (value) {
    startEnrichmentTimer();
  } else {
    if (enrichmentTimer) clearTimeout(enrichmentTimer);
    populateFormFields();
  }
});

watch(
  () => currentAccount.value?.custom_attributes,
  () => populateFormFields()
);

watch(locale, value => {
  if (['tr', 'en'].includes(value)) i18nLocale.value = value;
});
</script>

<template>
  <form class="min-h-dvh" @submit.prevent="handlePrimaryAction">
    <AssistantOnboardingLayout
      show-progress
      :current-step="questionStep"
      :total-steps="QUESTION_STEP_COUNT"
      :progress-label="
        t('ONBOARDING_NEXT.PROGRESS', {
          current: questionStep,
          total: QUESTION_STEP_COUNT,
        })
      "
      :primary-label="primaryLabel"
      :back-label="t('ONBOARDING_NEXT.BACK')"
      :show-back="canGoBack"
      :is-loading="isSubmitting || isVerifyingWebsite"
      @back="goBack"
    >
      <Transition :name="transitionName" mode="out-in">
        <section :key="currentStep" class="outline-none">
          <template v-if="currentStep === 'language'">
            <div class="flex items-center gap-3">
              <Avatar
                :name="accountName"
                :src="companyLogo"
                :size="44"
                rounded-full
              />
              <div class="min-w-0">
                <p class="m-0 text-xs font-medium text-n-slate-10">
                  {{ accountName }}
                </p>
                <p class="m-0 truncate text-sm text-n-slate-12">
                  {{ t('ONBOARDING_NEXT.WELCOME.ACCOUNT_READY') }}
                </p>
              </div>
            </div>

            <div class="mt-8">
              <h1
                id="language-step-title"
                ref="stepHeadingRef"
                tabindex="-1"
                class="text-xl font-semibold text-n-slate-12 outline-none sm:text-2xl"
              >
                {{ t('ONBOARDING_NEXT.LANGUAGE.TITLE') }}
              </h1>
              <p class="mt-2 max-w-lg text-sm leading-6 text-n-slate-11">
                {{
                  t('ONBOARDING_NEXT.LANGUAGE.DESCRIPTION', { name: userName })
                }}
              </p>
            </div>

            <fieldset aria-labelledby="language-step-title" class="mt-6">
              <legend class="sr-only">
                {{ t('ONBOARDING_NEXT.LANGUAGE.TITLE') }}
              </legend>
              <div class="grid gap-3 sm:grid-cols-2">
                <label
                  v-for="option in languageOptions"
                  :key="option.value"
                  class="flex cursor-pointer items-start gap-3 rounded-lg border p-4 transition-colors focus-within:ring-2 focus-within:ring-n-brand/20"
                  :class="
                    locale === option.value
                      ? 'border-n-brand bg-n-brand/5'
                      : 'border-n-weak bg-n-alpha-1 hover:border-n-strong'
                  "
                >
                  <span class="min-w-0 flex-1">
                    <span class="block text-sm font-medium text-n-slate-12">
                      {{ option.label }}
                    </span>
                    <span class="mt-1 block text-xs leading-5 text-n-slate-10">
                      {{ option.description }}
                    </span>
                  </span>
                  <input
                    v-model="locale"
                    type="radio"
                    name="language"
                    :value="option.value"
                    class="mt-1 size-4 flex-shrink-0 border-n-strong text-n-brand focus:ring-n-brand"
                  />
                </label>
              </div>
            </fieldset>
          </template>

          <template v-else-if="currentStep === 'website'">
            <h1
              ref="stepHeadingRef"
              tabindex="-1"
              class="text-xl font-semibold text-n-slate-12 outline-none sm:text-2xl"
            >
              {{ t('ONBOARDING_NEXT.WEBSITE.TITLE') }}
            </h1>
            <p class="mt-2 text-sm leading-6 text-n-slate-11">
              {{ t('ONBOARDING_NEXT.WEBSITE.DESCRIPTION') }}
            </p>

            <div
              v-if="isEnriching"
              class="mt-5 flex items-center gap-2 text-sm text-n-slate-10"
              role="status"
            >
              <Spinner :size="14" class="text-n-blue-10" />
              <span>{{ t('ONBOARDING_NEXT.WEBSITE.ENRICHING') }}</span>
            </div>

            <label class="mt-7 block text-sm font-medium text-n-slate-12">
              <span class="flex items-center justify-between gap-3">
                <span>{{ t('ONBOARDING_NEXT.WEBSITE.LABEL') }}</span>
                <span class="text-xs font-normal text-n-slate-9">
                  {{ t('ONBOARDING_NEXT.OPTIONAL') }}
                </span>
              </span>
              <span class="relative mt-2 block">
                <Icon
                  icon="i-lucide-globe-2"
                  class="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-9"
                />
                <input
                  ref="websiteInputRef"
                  v-model="website"
                  type="text"
                  inputmode="url"
                  name="website"
                  autocomplete="url"
                  spellcheck="false"
                  :placeholder="t('ONBOARDING_NEXT.WEBSITE.PLACEHOLDER')"
                  class="!mb-0 h-11 w-full rounded-lg border border-n-weak bg-n-alpha-1 !ps-10 !pe-3 text-sm text-n-slate-12 outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-n-brand"
                  :aria-invalid="Boolean(websiteError)"
                  :aria-describedby="websiteError ? 'website-error' : undefined"
                  @input="handleWebsiteInput"
                />
              </span>
            </label>
            <p
              v-if="websiteError"
              id="website-error"
              class="mt-2 text-sm text-n-ruby-11"
            >
              {{ websiteError }}
            </p>
            <button
              v-if="websiteError"
              type="button"
              class="mt-3 text-sm font-medium text-n-brand hover:underline"
              @click="continueWithoutWebsite"
            >
              {{ t('ONBOARDING_NEXT.WEBSITE.CONTINUE_WITHOUT') }}
            </button>
            <p class="mt-3 text-xs leading-5 text-n-slate-10">
              {{ t('ONBOARDING_NEXT.WEBSITE.HELP') }}
            </p>
          </template>

          <fieldset v-else-if="currentStep === 'tone'">
            <legend class="w-full">
              <span
                ref="stepHeadingRef"
                tabindex="-1"
                class="block text-xl font-semibold text-n-slate-12 outline-none sm:text-2xl"
              >
                {{ t('ONBOARDING_NEXT.TONE.TITLE') }}
              </span>
              <span class="mt-2 block text-sm leading-6 text-n-slate-11">
                {{ t('ONBOARDING_NEXT.TONE.DESCRIPTION') }}
              </span>
            </legend>

            <div class="mt-6 grid gap-3">
              <label
                v-for="option in toneOptions"
                :key="option.value"
                class="relative flex cursor-pointer items-center gap-4 rounded-lg border p-4 transition-colors focus-within:ring-2 focus-within:ring-n-brand/20"
                :class="
                  aiTone === option.value
                    ? 'border-n-brand bg-n-brand/5'
                    : 'border-n-weak bg-n-alpha-1 hover:border-n-strong'
                "
              >
                <span
                  class="flex size-9 flex-shrink-0 items-center justify-center rounded-md bg-n-alpha-2 text-n-slate-11"
                >
                  <Icon :icon="option.icon" class="size-4" />
                </span>
                <span class="min-w-0 flex-1">
                  <span class="block text-sm font-medium text-n-slate-12">
                    {{ option.label }}
                  </span>
                  <span class="mt-1 block text-xs leading-5 text-n-slate-10">
                    {{ option.description }}
                  </span>
                </span>
                <input
                  v-model="aiTone"
                  type="radio"
                  name="tone"
                  :value="option.value"
                  class="size-4 flex-shrink-0 border-n-strong text-n-brand focus:ring-n-brand"
                />
              </label>
            </div>
          </fieldset>

          <template v-else>
            <h1
              ref="stepHeadingRef"
              tabindex="-1"
              class="text-xl font-semibold text-n-slate-12 outline-none sm:text-2xl"
            >
              {{ t('ONBOARDING_NEXT.REVIEW.TITLE') }}
            </h1>
            <p class="mt-2 text-sm leading-6 text-n-slate-11">
              {{ t('ONBOARDING_NEXT.REVIEW.DESCRIPTION') }}
            </p>

            <dl class="mt-6 divide-y divide-n-weak border-y border-n-weak">
              <div class="flex items-center gap-4 py-4">
                <dt class="w-28 flex-shrink-0 text-sm text-n-slate-10">
                  {{ t('ONBOARDING_NEXT.REVIEW.WEBSITE') }}
                </dt>
                <dd class="m-0 min-w-0 flex-1 text-sm text-n-slate-12">
                  <template v-if="verifiedWebsite">
                    <span class="block truncate font-medium">
                      {{ verifiedWebsite.title || verifiedWebsite.hostname }}
                    </span>
                    <span class="mt-0.5 block truncate text-xs text-n-slate-10">
                      {{ verifiedWebsite.hostname }}
                    </span>
                    <span class="mt-1 block text-xs text-n-slate-10">
                      {{ t('ONBOARDING_NEXT.REVIEW.WEBSITE_CONFIRMATION') }}
                    </span>
                  </template>
                  <template v-else>
                    {{ t('ONBOARDING_NEXT.REVIEW.NO_WEBSITE') }}
                  </template>
                </dd>
                <button
                  type="button"
                  class="text-sm font-medium text-n-brand hover:underline"
                  @click="editStep('website')"
                >
                  {{ t('ONBOARDING_NEXT.REVIEW.EDIT') }}
                </button>
              </div>
              <div class="flex items-center gap-4 py-4">
                <dt class="w-28 flex-shrink-0 text-sm text-n-slate-10">
                  {{ t('ONBOARDING_NEXT.REVIEW.TONE') }}
                </dt>
                <dd class="m-0 min-w-0 flex-1 text-sm text-n-slate-12">
                  {{ selectedToneLabel }}
                </dd>
                <button
                  type="button"
                  class="text-sm font-medium text-n-brand hover:underline"
                  @click="editStep('tone')"
                >
                  {{ t('ONBOARDING_NEXT.REVIEW.EDIT') }}
                </button>
              </div>
              <div class="flex items-center gap-4 py-4">
                <dt class="w-28 flex-shrink-0 text-sm text-n-slate-10">
                  {{ t('ONBOARDING_NEXT.REVIEW.LANGUAGE') }}
                </dt>
                <dd class="m-0 min-w-0 flex-1 text-sm text-n-slate-12">
                  {{ selectedLanguageLabel }}
                </dd>
                <button
                  type="button"
                  class="text-sm font-medium text-n-brand hover:underline"
                  @click="editStep('language')"
                >
                  {{ t('ONBOARDING_NEXT.REVIEW.EDIT') }}
                </button>
              </div>
            </dl>
          </template>
        </section>
      </Transition>
    </AssistantOnboardingLayout>
  </form>
</template>

<style scoped>
.step-forward-enter-active,
.step-forward-leave-active,
.step-backward-enter-active,
.step-backward-leave-active {
  transition:
    opacity 180ms ease,
    transform 180ms ease;
}

.step-forward-enter-from,
.step-backward-leave-to {
  opacity: 0;
  transform: translateX(12px);
}

.step-forward-leave-to,
.step-backward-enter-from {
  opacity: 0;
  transform: translateX(-12px);
}

@media (prefers-reduced-motion: reduce) {
  .step-forward-enter-active,
  .step-forward-leave-active,
  .step-backward-enter-active,
  .step-backward-leave-active {
    transition: none;
  }
}
</style>
