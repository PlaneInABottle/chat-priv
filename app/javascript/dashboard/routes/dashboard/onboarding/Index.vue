<script setup>
import { ref, computed, nextTick, onMounted, onUnmounted, watch } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert, useTrack } from 'dashboard/composables';
import { ONBOARDING_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import OnboardingLayout from './OnboardingLayout.vue';
import OnboardingSection from './OnboardingSection.vue';
import OnboardingFormRow from './OnboardingFormRow.vue';
import OnboardingFormSelect from './OnboardingFormSelect.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AiAgentOnboardingAPI from 'dashboard/api/aiAgentOnboarding';
import {
  AI_PURPOSE_OPTIONS,
  AI_TONE_OPTIONS,
  COMPANY_SIZE_OPTIONS,
  INDUSTRY_OPTIONS,
  REFERRAL_SOURCE_OPTIONS,
  USER_ROLE_OPTIONS,
} from './constants';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountId, currentAccount } = useAccount();
const { enabledLanguages } = useConfig();
const currentUser = useMapGetter('getCurrentUser');

const userRole = ref('');
const website = ref('');
const locale = ref('');
const timezone = ref('');
const companySize = ref('');
const industry = ref('');
const referralSource = ref('');
const aiPurpose = ref('support');
const aiTone = ref('friendly');
const isSubmitting = ref(false);
const isEditingWebsite = ref(false);
const websiteInput = ref(null);
const showErrorOnFields = ref(false);
const onboardingPhase = ref('details');
const onboardingState = ref(null);
const isCompleting = ref(false);

const validationRules = {
  userRole: {},
  website: {},
  locale: {},
  timezone: {},
  companySize: {},
  industry: {},
  referralSource: {},
};

const v$ = useVuelidate(validationRules, {
  userRole,
  website,
  locale,
  timezone,
  companySize,
  industry,
  referralSource,
});

const importStatus = computed(() => onboardingState.value?.status);
const importStage = computed(() => onboardingState.value?.stage || 'queued');
const isImportRunning = computed(() =>
  ['pending', 'running'].includes(importStatus.value)
);
const draftIsReady = computed(() =>
  ['applied', 'ready', 'failed', 'fallback'].includes(importStatus.value)
);
const assistantId = computed(() => onboardingState.value?.ai_agent?.id);
const canReviewDraft = computed(() =>
  Boolean(assistantId.value && (draftIsReady.value || isImportRunning.value))
);
const hasWebsiteImport = computed(() =>
  Boolean(onboardingState.value?.website_import)
);

let importPollTimer = null;

const stopImportPolling = () => {
  if (importPollTimer) clearTimeout(importPollTimer);
  importPollTimer = null;
};

const loadOnboardingState = async () => {
  try {
    const { data } = await AiAgentOnboardingAPI.get();
    onboardingState.value = data;
    if (data.status !== 'not_started') onboardingPhase.value = 'building';

    stopImportPolling();
    if (['pending', 'running'].includes(data.status)) {
      importPollTimer = setTimeout(loadOnboardingState, 1500);
    }
  } catch {
    stopImportPolling();
    importPollTimer = setTimeout(loadOnboardingState, 3000);
  }
};

const userName = computed(() => currentUser.value?.name || '');
const userEmail = computed(() => currentUser.value?.email || '');
const accountName = computed(() => currentAccount.value?.name || '');
const enrichmentTimedOut = ref(false);
const isEnriching = computed(
  () =>
    !enrichmentTimedOut.value &&
    currentAccount.value?.custom_attributes?.onboarding_step === 'enrichment'
);
const companyLogo = computed(() => {
  const logos = currentAccount.value?.custom_attributes?.brand_info?.logos;
  if (!logos?.length) return '';
  const square = logos.find(l => l.resolution?.aspect_ratio === 1);
  return (square || logos[0])?.url || '';
});

const languageOptions = computed(() => {
  const langs = [...(enabledLanguages || [])];
  return langs
    .sort((a, b) => a.iso_639_1_code.localeCompare(b.iso_639_1_code))
    .map(l => ({ value: l.iso_639_1_code, label: l.name }));
});

const timezoneOptions = computed(() => {
  try {
    return Intl.supportedValuesOf('timeZone').map(tz => ({
      value: tz,
      label: tz.replace(/_/g, ' '),
    }));
  } catch {
    return [];
  }
});

const aiPurposeOptions = computed(() =>
  AI_PURPOSE_OPTIONS.map(value => ({
    value,
    label: t(`ONBOARDING_NEXT.AI_PURPOSE_OPTIONS.${value.toUpperCase()}`),
  }))
);

const aiToneOptions = computed(() =>
  AI_TONE_OPTIONS.map(value => ({
    value,
    label: t(`ONBOARDING_NEXT.AI_TONE_OPTIONS.${value.toUpperCase()}`),
  }))
);

// Best-effort match browser language to enabled Chatwoot locales.
// Tries exact match first (e.g. 'pt_BR'), then base language (e.g. 'pt'),
// falls back to account locale or 'en'.
const detectBestLocale = () => {
  const codes = (enabledLanguages || []).map(l => l.iso_639_1_code);
  const browserLang = navigator.language?.replace('-', '_');
  const accountLocale = currentAccount.value?.locale || 'en';
  if (!browserLang) return accountLocale;

  if (codes.includes(browserLang)) return browserLang;
  const base = browserLang.split('_')[0];
  if (codes.includes(base)) return base;

  return accountLocale;
};

// Snapshot of auto-populated values to detect user edits at submit time
const initialValues = ref({});

const snapshotInitialValues = () => {
  initialValues.value = {
    website: website.value,
    company_size: companySize.value,
    industry: industry.value,
  };
};

// Idempotent: only fills empty fields, so late-arriving enrichment data
// populates untouched fields without clobbering user edits.
const populateFormFields = () => {
  const account = currentAccount.value;
  const attrs = account?.custom_attributes || {};
  const brandInfo = attrs.brand_info;

  if (!locale.value) locale.value = detectBestLocale();
  if (!website.value) {
    website.value = attrs.website || brandInfo?.domain || '';
  }
  if (!timezone.value) {
    timezone.value =
      attrs.timezone || Intl.DateTimeFormat().resolvedOptions().timeZone || '';
  }
  if (!companySize.value) companySize.value = attrs.company_size || '';
  if (!industry.value) {
    industry.value =
      attrs.industry || brandInfo?.industries?.[0]?.industry || '';
  }
  if (!referralSource.value) referralSource.value = attrs.referral_source || '';

  snapshotInitialValues();
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
  if (
    currentAccount.value?.custom_attributes?.onboarding_step === 'ai_assistant'
  ) {
    loadOnboardingState();
  }
});

onUnmounted(() => {
  if (enrichmentTimer) clearTimeout(enrichmentTimer);
  stopImportPolling();
});

watch(isEnriching, newVal => {
  if (newVal) {
    startEnrichmentTimer();
  } else {
    if (enrichmentTimer) clearTimeout(enrichmentTimer);
    populateFormFields();
  }
});

// Re-populate when account data arrives after mount, or when brand_info
// appears after enrichment. populateFormFields is idempotent so this is safe.
watch(
  () => currentAccount.value?.custom_attributes,
  () => populateFormFields()
);

const enableWebsiteEditing = () => {
  isEditingWebsite.value = true;
  nextTick(() => websiteInput.value?.focus());
};

const handleWebsiteEnter = () => {
  websiteInput.value?.blur();
};

const handleSubmit = async () => {
  // Block submit while enrichment is still running so users can't bypass
  // the form with empty values — the controller would otherwise clear
  // onboarding_step and persist incomplete data.
  if (isEnriching.value) return;

  v$.value.$touch();
  if (v$.value.$invalid) {
    useAlert(t('ONBOARDING_NEXT.VALIDATION_ERROR'));
    showErrorOnFields.value = true;
    setTimeout(() => {
      showErrorOnFields.value = false;
    }, 600);
    return;
  }

  isSubmitting.value = true;
  try {
    const { data } = await AiAgentOnboardingAPI.create({
      account: {
        locale: locale.value,
        website: website.value,
        industry: industry.value,
        company_size: companySize.value,
        timezone: timezone.value,
        referral_source: referralSource.value,
        user_role: userRole.value,
      },
      assistant: {
        purpose: aiPurpose.value,
        tone: aiTone.value,
      },
    });
    onboardingState.value = data;
    onboardingPhase.value = 'building';

    const init = initialValues.value;
    const enrichableFields = {
      website: website.value,
      company_size: companySize.value,
      industry: industry.value,
    };

    useTrack(ONBOARDING_EVENTS.ACCOUNT_DETAILS_COMPLETED, {
      has_enriched_data: Boolean(
        currentAccount.value?.custom_attributes?.brand_info
      ),
      fields_changed: Object.entries(enrichableFields)
        .filter(([key, val]) => val !== init[key])
        .map(([key]) => key),
      user_role: userRole.value,
      company_size: companySize.value,
      industry: industry.value,
      referral_source: referralSource.value,
    });

    if (['pending', 'running'].includes(data.status)) {
      importPollTimer = setTimeout(loadOnboardingState, 1500);
    }
  } catch {
    useAlert(t('ONBOARDING_NEXT.ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};

const reviewAssistant = async () => {
  if (!assistantId.value) return;

  isCompleting.value = true;
  try {
    await AiAgentOnboardingAPI.complete();
    store.commit('RESET_ONBOARDING', accountId.value);
    router.push({
      name: 'ai_agent_instructions',
      params: { id: assistantId.value, accountId: accountId.value },
    });
  } catch {
    useAlert(t('ONBOARDING_NEXT.ERROR'));
  } finally {
    isCompleting.value = false;
  }
};
</script>

<template>
  <form v-if="onboardingPhase === 'details'" @submit.prevent="handleSubmit">
    <OnboardingLayout
      :greeting="t('ONBOARDING_NEXT.GREETING', { name: userName })"
      :subtitle="t('ONBOARDING_NEXT.SUBTITLE')"
      :continue-label="t('ONBOARDING_NEXT.CONTINUE')"
      :is-loading="isSubmitting"
      :disabled="isEnriching"
    >
      <OnboardingSection
        :title="t('ONBOARDING_NEXT.YOUR_DETAILS')"
        icon="i-lucide-user"
      >
        <div class="flex items-center gap-2 px-3 py-3">
          <Avatar :name="userName" :size="16" rounded-full />
          <span class="text-sm font-medium text-n-slate-12">
            {{ userName }}
          </span>
        </div>
        <OnboardingFormRow
          :title="t('ONBOARDING_NEXT.FIELDS.EMAIL')"
          icon="i-lucide-mail"
        >
          <div class="flex items-center justify-end gap-1.5">
            <span class="text-sm text-n-slate-12">{{ userEmail }}</span>
            <Icon
              v-tooltip="t('ONBOARDING_NEXT.EMAIL_VERIFIED')"
              icon="i-lucide-circle-check"
              class="size-4 text-n-teal-11 flex-shrink-0"
            />
          </div>
        </OnboardingFormRow>
        <OnboardingFormRow
          :title="t('ONBOARDING_NEXT.FIELDS.YOUR_ROLE')"
          icon="i-lucide-user"
        >
          <OnboardingFormSelect
            v-model="userRole"
            :has-error="showErrorOnFields && v$.userRole.$error"
            :options="USER_ROLE_OPTIONS"
            :placeholder="t('ONBOARDING_NEXT.PLACEHOLDERS.SELECT_ROLE')"
          />
        </OnboardingFormRow>
      </OnboardingSection>

      <OnboardingSection
        :title="t('ONBOARDING_NEXT.COMPANY_DETAILS')"
        icon="i-lucide-briefcase-business"
      >
        <div
          v-if="isEnriching"
          class="flex items-center justify-center gap-3 py-8"
        >
          <Spinner :size="16" class="text-n-blue-10" />
          <span class="text-sm text-n-slate-11">
            {{ t('ONBOARDING_NEXT.SETTING_UP') }}
          </span>
        </div>
        <template v-else>
          <div class="flex items-center gap-2 px-3 py-3">
            <img
              v-if="companyLogo"
              :src="companyLogo"
              :alt="accountName"
              class="size-4 object-contain"
            />
            <span class="text-sm font-medium text-n-slate-12">
              {{ accountName }}
            </span>
          </div>
          <OnboardingFormRow
            :title="t('ONBOARDING_NEXT.FIELDS.WEBSITE')"
            icon="i-lucide-globe"
          >
            <div class="flex items-center justify-end gap-2">
              <InlineInput
                ref="websiteInput"
                v-model="website"
                :readonly="!isEditingWebsite"
                :placeholder="t('ONBOARDING_NEXT.PLACEHOLDERS.ENTER_WEBSITE')"
                :custom-input-class="[
                  'w-auto text-end px-1 py-0.5 -my-0.5 mx-0 placeholder:text-n-slate-9 rounded',
                  { 'animate-shake': showErrorOnFields && v$.website.$error },
                ]"
                @enter-press="handleWebsiteEnter"
                @blur="isEditingWebsite = false"
              />
              <NextButton
                v-tooltip="t('ONBOARDING_NEXT.EDIT_WEBSITE')"
                type="button"
                icon="i-lucide-pencil"
                :aria-label="t('ONBOARDING_NEXT.EDIT_WEBSITE')"
                slate
                xs
                ghost
                @click="enableWebsiteEditing"
              />
            </div>
          </OnboardingFormRow>
          <OnboardingFormRow
            :title="t('ONBOARDING_NEXT.FIELDS.LANGUAGE')"
            icon="i-lucide-languages"
          >
            <OnboardingFormSelect
              v-model="locale"
              :has-error="showErrorOnFields && v$.locale.$error"
              :options="languageOptions"
            />
          </OnboardingFormRow>
          <OnboardingFormRow
            :title="t('ONBOARDING_NEXT.FIELDS.TIMEZONE')"
            icon="i-lucide-clock"
          >
            <OnboardingFormSelect
              v-model="timezone"
              :has-error="showErrorOnFields && v$.timezone.$error"
              :options="timezoneOptions"
              :placeholder="t('ONBOARDING_NEXT.PLACEHOLDERS.SELECT_TIMEZONE')"
            />
          </OnboardingFormRow>
          <OnboardingFormRow
            :title="t('ONBOARDING_NEXT.FIELDS.INDUSTRY')"
            icon="i-lucide-factory"
          >
            <OnboardingFormSelect
              v-model="industry"
              :has-error="showErrorOnFields && v$.industry.$error"
              :options="INDUSTRY_OPTIONS"
              :placeholder="t('ONBOARDING_NEXT.PLACEHOLDERS.SELECT_INDUSTRY')"
            />
          </OnboardingFormRow>
          <OnboardingFormRow
            :title="t('ONBOARDING_NEXT.FIELDS.COMPANY_SIZE')"
            icon="i-lucide-users"
          >
            <OnboardingFormSelect
              v-model="companySize"
              :has-error="showErrorOnFields && v$.companySize.$error"
              :options="COMPANY_SIZE_OPTIONS"
              :placeholder="
                t('ONBOARDING_NEXT.PLACEHOLDERS.SELECT_COMPANY_SIZE')
              "
            />
          </OnboardingFormRow>
          <OnboardingFormRow
            :title="t('ONBOARDING_NEXT.FIELDS.REFERRAL_SOURCE')"
            icon="i-lucide-megaphone"
          >
            <OnboardingFormSelect
              v-model="referralSource"
              :has-error="showErrorOnFields && v$.referralSource.$error"
              :options="REFERRAL_SOURCE_OPTIONS"
              :placeholder="
                t('ONBOARDING_NEXT.PLACEHOLDERS.SELECT_REFERRAL_SOURCE')
              "
            />
          </OnboardingFormRow>
        </template>
      </OnboardingSection>

      <OnboardingSection
        :title="t('ONBOARDING_NEXT.ASSISTANT_DETAILS')"
        icon="i-lucide-bot"
      >
        <OnboardingFormRow
          :title="t('ONBOARDING_NEXT.FIELDS.AI_PURPOSE')"
          icon="i-lucide-goal"
        >
          <OnboardingFormSelect
            v-model="aiPurpose"
            :options="aiPurposeOptions"
          />
        </OnboardingFormRow>
        <OnboardingFormRow
          :title="t('ONBOARDING_NEXT.FIELDS.AI_TONE')"
          icon="i-lucide-message-circle"
        >
          <OnboardingFormSelect v-model="aiTone" :options="aiToneOptions" />
        </OnboardingFormRow>
        <div class="flex items-start gap-3 border-t border-n-weak px-3 py-3">
          <Icon
            icon="i-lucide-shield-check"
            class="mt-0.5 size-4 flex-shrink-0 text-n-teal-11"
          />
          <p class="m-0 text-xs leading-5 text-n-slate-11">
            {{ t('ONBOARDING_NEXT.ASSISTANT_DRAFT_HELP') }}
          </p>
        </div>
      </OnboardingSection>
    </OnboardingLayout>
  </form>

  <main
    v-else
    class="flex min-h-screen w-full items-center justify-center bg-n-surface-2 px-4 py-12"
  >
    <section class="w-full max-w-2xl">
      <div class="mb-8 flex items-start gap-4">
        <div
          class="flex size-11 flex-shrink-0 items-center justify-center rounded-lg bg-n-blue-3 text-n-blue-11"
        >
          <Icon icon="i-lucide-bot" class="size-5" />
        </div>
        <div>
          <h1 class="m-0 text-2xl font-semibold text-n-slate-12">
            {{ t('ONBOARDING_NEXT.BUILDING.TITLE') }}
          </h1>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ t('ONBOARDING_NEXT.BUILDING.DESCRIPTION') }}
          </p>
        </div>
      </div>

      <div
        v-if="hasWebsiteImport"
        role="status"
        aria-live="polite"
        class="border-y border-n-weak py-2"
      >
        <div
          v-for="stage in ['crawling', 'generating', 'applying']"
          :key="stage"
          class="flex min-h-14 items-center gap-3 border-b border-n-weak px-2 last:border-b-0"
        >
          <Spinner
            v-if="isImportRunning && importStage === stage"
            :size="16"
            class="text-n-blue-10"
          />
          <Icon
            v-else
            :icon="
              draftIsReady ||
              ['generating', 'applying'].indexOf(importStage) >
                ['generating', 'applying'].indexOf(stage)
                ? 'i-lucide-circle-check'
                : 'i-lucide-circle'
            "
            class="size-4 flex-shrink-0"
            :class="draftIsReady ? 'text-n-teal-11' : 'text-n-slate-8'"
          />
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`ONBOARDING_NEXT.BUILDING.STAGES.${stage.toUpperCase()}`) }}
          </span>
        </div>
      </div>

      <div
        v-else
        class="flex items-center gap-3 border-y border-n-weak px-2 py-5"
      >
        <Icon icon="i-lucide-circle-check" class="size-5 text-n-teal-11" />
        <div>
          <p class="m-0 text-sm font-medium text-n-slate-12">
            {{ t('ONBOARDING_NEXT.BUILDING.DRAFT_READY') }}
          </p>
          <p class="mb-0 mt-1 text-xs text-n-slate-10">
            {{ t('ONBOARDING_NEXT.BUILDING.DRAFT_READY_HELP') }}
          </p>
        </div>
      </div>

      <div
        v-if="importStatus === 'failed'"
        class="mt-5 flex items-start gap-3 rounded-lg border border-n-amber-5 bg-n-amber-2 p-4"
      >
        <Icon icon="i-lucide-info" class="mt-0.5 size-4 text-n-amber-11" />
        <p class="m-0 text-sm text-n-amber-12">
          {{ t('ONBOARDING_NEXT.BUILDING.FALLBACK') }}
        </p>
      </div>

      <div v-if="canReviewDraft" class="mt-6 flex justify-end">
        <NextButton
          icon="i-lucide-arrow-right"
          :label="
            isImportRunning
              ? t('ONBOARDING_NEXT.BUILDING.REVIEW_STARTER')
              : t('ONBOARDING_NEXT.BUILDING.REVIEW')
          "
          :is-loading="isCompleting"
          @click="reviewAssistant"
        />
      </div>
    </section>
  </main>
</template>
