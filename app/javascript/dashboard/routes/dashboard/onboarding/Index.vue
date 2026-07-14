<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert, useTrack } from 'dashboard/composables';
import { ONBOARDING_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import OnboardingLayout from './shared/OnboardingLayout.vue';
import OnboardingSection from './shared/OnboardingSection.vue';
import OnboardingFormRow from './account-details/OnboardingFormRow.vue';
import OnboardingFormSelect from './account-details/OnboardingFormSelect.vue';
import { useAccountEnrichment } from './account-details/useAccountEnrichment';
import AiAgentOnboardingAPI from 'dashboard/api/aiAgentOnboarding';
import {
  AI_PURPOSE_OPTIONS,
  AI_TONE_OPTIONS,
  COMPANY_SIZE_OPTIONS,
  INDUSTRY_OPTIONS,
  REFERRAL_SOURCE_OPTIONS,
  USER_ROLE_OPTIONS,
} from './shared/constants';

const { t, locale: i18nLocale } = useI18n();
const router = useRouter();
const store = useStore();
const { accountId, currentAccount } = useAccount();
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
const websiteError = ref('');

const userName = computed(() => currentUser.value?.name || '');
const userEmail = computed(() => currentUser.value?.email || '');
const accountName = computed(() => currentAccount.value?.name || '');
const { isEnriching, getChangedFields } = useAccountEnrichment({
  locale,
  website,
  timezone,
  companySize,
  industry,
  referralSource,
});
const companyLogo = computed(() => {
  const logos = currentAccount.value?.custom_attributes?.brand_info?.logos;
  if (!logos?.length) return '';
  const square = logos.find(l => l.resolution?.aspect_ratio === 1);
  return (square || logos[0])?.url || '';
});

const languageOptions = computed(() => {
  return [
    { value: 'tr', label: t('ONBOARDING_NEXT.LANGUAGES.TR') },
    { value: 'en', label: t('ONBOARDING_NEXT.LANGUAGES.EN') },
  ];
});

const optionTranslationKey = value =>
  value
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '_')
    .replace(/^_|_$/g, '');

const localizedOptions = (options, group) =>
  options.map(option => ({
    ...option,
    label: t(
      `ONBOARDING_NEXT.OPTION_LABELS.${group}.${optionTranslationKey(option.value)}`
    ),
  }));

const userRoleOptions = computed(() =>
  localizedOptions(USER_ROLE_OPTIONS, 'ROLES')
);
const industryOptions = computed(() =>
  localizedOptions(INDUSTRY_OPTIONS, 'INDUSTRIES')
);
const referralSourceOptions = computed(() =>
  localizedOptions(REFERRAL_SOURCE_OPTIONS, 'REFERRALS')
);

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

onMounted(() => {
  useTrack(ONBOARDING_EVENTS.ACCOUNT_DETAILS_VISITED);
});

const handleSubmit = async () => {
  // Block submit while enrichment is still running so users can't bypass
  // the form with empty values — the controller would otherwise clear
  // onboarding_step and persist incomplete data.
  if (isEnriching.value || isSubmitting.value) return;

  const fieldsChanged = getChangedFields();

  isSubmitting.value = true;
  websiteError.value = '';
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
    useTrack(ONBOARDING_EVENTS.ACCOUNT_DETAILS_COMPLETED, {
      has_enriched_data: Boolean(
        currentAccount.value?.custom_attributes?.brand_info
      ),
      fields_changed: fieldsChanged,
      user_role: userRole.value,
      company_size: companySize.value,
      industry: industry.value,
      referral_source: referralSource.value,
    });

    store.commit('RESET_ONBOARDING', accountId.value);
    router.push({
      name: 'ai_agent_instructions',
      params: { id: data.ai_agent.id, accountId: accountId.value },
    });
  } catch (error) {
    if (error.response?.data?.code === 'invalid_website') {
      websiteError.value = t('ONBOARDING_NEXT.WEBSITE_ERROR');
    } else {
      useAlert(t('ONBOARDING_NEXT.ERROR'));
    }
  } finally {
    isSubmitting.value = false;
  }
};

watch(locale, value => {
  if (['tr', 'en'].includes(value)) i18nLocale.value = value;
});
</script>

<template>
  <form @submit.prevent="handleSubmit">
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
            :options="userRoleOptions"
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
            <div class="flex min-w-0 flex-col items-end gap-1">
              <input
                v-model="website"
                type="text"
                inputmode="url"
                name="website"
                autocomplete="url"
                spellcheck="false"
                :placeholder="t('ONBOARDING_NEXT.PLACEHOLDERS.ENTER_WEBSITE')"
                class="h-8 min-w-0 w-full border-0 bg-transparent px-1 text-end text-sm text-n-slate-12 outline-none placeholder:text-n-slate-9 focus:ring-0 sm:w-64"
                @input="websiteError = ''"
              />
              <span v-if="websiteError" class="text-xs text-n-ruby-11">
                {{ websiteError }}
              </span>
            </div>
          </OnboardingFormRow>
          <OnboardingFormRow
            :title="t('ONBOARDING_NEXT.FIELDS.LANGUAGE')"
            icon="i-lucide-languages"
          >
            <OnboardingFormSelect v-model="locale" :options="languageOptions" />
          </OnboardingFormRow>
          <OnboardingFormRow
            :title="t('ONBOARDING_NEXT.FIELDS.TIMEZONE')"
            icon="i-lucide-clock"
          >
            <OnboardingFormSelect
              v-model="timezone"
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
              :options="industryOptions"
              :placeholder="t('ONBOARDING_NEXT.PLACEHOLDERS.SELECT_INDUSTRY')"
            />
          </OnboardingFormRow>
          <OnboardingFormRow
            :title="t('ONBOARDING_NEXT.FIELDS.COMPANY_SIZE')"
            icon="i-lucide-users"
          >
            <OnboardingFormSelect
              v-model="companySize"
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
              :options="referralSourceOptions"
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
</template>
