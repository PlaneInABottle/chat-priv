<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import VoiceAPI from 'dashboard/api/voice';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import {
  buildTextSetupProgress,
  buildVoiceSetupProgress,
} from './setupProgress';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountId, currentAccount } = useAccount();

const textAgents = useMapGetter('aiAgent/getAiAgents');
const isFeatureEnabled = useMapGetter('accounts/isFeatureEnabledonAccount');
const voiceAgents = ref([]);
const isLoading = ref(true);
const hasLoaded = ref(false);

const hasTextAi = computed(() =>
  isFeatureEnabled.value(accountId.value, FEATURE_FLAGS.AI_AGENT)
);
const hasVoiceAi = computed(() =>
  isFeatureEnabled.value(accountId.value, FEATURE_FLAGS.VOICE_AI)
);

const textProgress = computed(() => buildTextSetupProgress(textAgents.value));
const voiceProgress = computed(() =>
  buildVoiceSetupProgress(voiceAgents.value)
);

const textStepLabels = computed(() => ({
  assistant: t('AI_SETUP.TEXT.STEPS.ASSISTANT'),
  instructions: t('AI_SETUP.TEXT.STEPS.INSTRUCTIONS'),
  inbox: t('AI_SETUP.TEXT.STEPS.INBOX'),
  test: t('AI_SETUP.TEXT.STEPS.TEST'),
  active: t('AI_SETUP.TEXT.STEPS.ACTIVE'),
}));
const voiceStepLabels = computed(() => ({
  assistant: t('AI_SETUP.VOICE.STEPS.ASSISTANT'),
  instructions: t('AI_SETUP.VOICE.STEPS.INSTRUCTIONS'),
  inbox: t('AI_SETUP.VOICE.STEPS.INBOX'),
  test: t('AI_SETUP.VOICE.STEPS.TEST'),
  active: t('AI_SETUP.VOICE.STEPS.ACTIVE'),
}));
const trackActionLabels = computed(() => ({
  TEXT: {
    start: t('AI_SETUP.TEXT.START'),
    continue: t('AI_SETUP.TEXT.CONTINUE'),
    manage: t('AI_SETUP.TEXT.MANAGE'),
  },
  VOICE: {
    start: t('AI_SETUP.VOICE.START'),
    continue: t('AI_SETUP.VOICE.CONTINUE'),
    manage: t('AI_SETUP.VOICE.MANAGE'),
  },
}));

const statusLabel = progress => {
  if (progress.ready) return t('AI_SETUP.STATUS.READY');
  if (progress.agent) return t('AI_SETUP.STATUS.IN_PROGRESS');
  return t('AI_SETUP.STATUS.NOT_STARTED');
};

const statusClass = progress => {
  if (progress.ready) return 'bg-n-teal-3 text-n-teal-11';
  if (progress.agent) return 'bg-n-blue-3 text-n-blue-11';
  return 'bg-n-alpha-2 text-n-slate-11';
};

const actionLabel = (progress, mode) => {
  if (progress.ready) return trackActionLabels.value[mode].manage;
  if (progress.agent) return trackActionLabels.value[mode].continue;
  return trackActionLabels.value[mode].start;
};

const tracks = computed(() => {
  const availableTracks = [];
  if (hasTextAi.value) {
    availableTracks.push({
      key: 'TEXT',
      icon: 'i-lucide-message-square-text',
      title: t('AI_SETUP.TEXT.TITLE'),
      description: t('AI_SETUP.TEXT.DESCRIPTION'),
      progress: textProgress.value,
      labels: textStepLabels.value,
    });
  }
  if (hasVoiceAi.value) {
    availableTracks.push({
      key: 'VOICE',
      icon: 'i-lucide-phone-call',
      title: t('AI_SETUP.VOICE.TITLE'),
      description: t('AI_SETUP.VOICE.DESCRIPTION'),
      progress: voiceProgress.value,
      labels: voiceStepLabels.value,
    });
  }
  return availableTracks;
});

const openTextSetup = () => {
  const { agent, steps, ready } = textProgress.value;
  if (!agent) return router.push({ name: 'ai_agent_new' });
  if (ready) return router.push({ name: 'ai_agents' });

  const firstIncomplete = steps.find(step => !step.complete)?.key;
  const routeNames = {
    instructions: 'ai_agent_instructions',
    inbox: 'ai_agent_detail',
    test: 'ai_agent_test',
    active: 'ai_agent_instructions',
  };
  return router.push({
    name: routeNames[firstIncomplete] || 'ai_agent_instructions',
    params: { id: agent.id },
  });
};

const openVoiceSetup = () => {
  const { agent, steps, ready } = voiceProgress.value;
  const firstIncomplete = steps.find(step => !step.complete)?.key;
  return router.push({
    name: 'voice_ai_settings',
    query: {
      section:
        agent && !ready && firstIncomplete === 'test' ? 'test' : 'agents',
    },
  });
};

const openTrack = key => (key === 'TEXT' ? openTextSetup() : openVoiceSetup());

const loadSetupProgress = async () => {
  if (hasLoaded.value || !currentAccount.value?.id) return;
  if (!hasTextAi.value && !hasVoiceAi.value) {
    hasLoaded.value = true;
    isLoading.value = false;
    return;
  }

  hasLoaded.value = true;
  try {
    const requests = [];
    if (hasTextAi.value) requests.push(store.dispatch('aiAgent/get'));
    if (hasVoiceAi.value) {
      requests.push(
        VoiceAPI.getAgents().then(response => {
          voiceAgents.value = response.data?.payload || [];
        })
      );
    }
    await Promise.all(requests);
  } catch {
    useAlert(t('AI_SETUP.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

watch([currentAccount, hasTextAi, hasVoiceAi], loadSetupProgress, {
  immediate: true,
});
</script>

<template>
  <SettingsLayout :is-loading="isLoading">
    <template #header>
      <BaseSettingsHeader
        :title="t('AI_SETUP.TITLE')"
        :description="t('AI_SETUP.DESCRIPTION')"
      />
    </template>

    <template #body>
      <div v-if="tracks.length" class="grid max-w-5xl gap-6 lg:grid-cols-2">
        <article
          v-for="track in tracks"
          :key="track.key"
          class="flex min-w-0 flex-col rounded-lg border border-n-weak bg-n-solid-1 p-5 sm:p-6"
        >
          <header class="flex items-start justify-between gap-4">
            <div class="flex min-w-0 items-center gap-3">
              <span
                class="flex size-9 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2"
              >
                <Icon :icon="track.icon" class="size-4 text-n-slate-12" />
              </span>
              <h2 class="m-0 text-xl font-semibold text-n-slate-12">
                {{ track.title }}
              </h2>
            </div>
            <span
              class="flex-shrink-0 rounded-full px-2.5 py-1 text-xs font-medium"
              :class="statusClass(track.progress)"
            >
              {{ statusLabel(track.progress) }}
            </span>
          </header>

          <p class="mb-0 mt-4 max-w-prose text-sm leading-6 text-n-slate-11">
            {{ track.description }}
          </p>

          <div class="mt-6 flex items-center justify-between gap-3 text-xs">
            <span class="font-medium text-n-slate-12">
              {{
                t('AI_SETUP.PROGRESS', {
                  complete: track.progress.completedCount,
                  total: track.progress.steps.length,
                })
              }}
            </span>
            <span v-if="track.progress.agent" class="truncate text-n-slate-10">
              {{ track.progress.agent.name }}
            </span>
          </div>
          <div
            class="mt-2 h-1.5 overflow-hidden rounded-full bg-n-alpha-2"
            role="progressbar"
            :aria-valuenow="track.progress.completedCount"
            aria-valuemin="0"
            :aria-valuemax="track.progress.steps.length"
          >
            <div
              class="h-full rounded-full bg-n-brand transition-all"
              :style="{
                width: `${
                  (track.progress.completedCount /
                    track.progress.steps.length) *
                  100
                }%`,
              }"
            />
          </div>

          <ol class="m-0 mt-5 flex list-none flex-col p-0">
            <li
              v-for="step in track.progress.steps"
              :key="step.key"
              class="flex min-h-10 items-center gap-3 border-b border-n-weak py-2.5 last:border-b-0"
            >
              <Icon
                :icon="
                  step.complete ? 'i-lucide-circle-check' : 'i-lucide-circle'
                "
                class="size-4 flex-shrink-0"
                :class="step.complete ? 'text-n-teal-10' : 'text-n-slate-8'"
              />
              <span
                class="text-sm"
                :class="step.complete ? 'text-n-slate-10' : 'text-n-slate-12'"
              >
                {{ track.labels[step.key] }}
              </span>
            </li>
          </ol>

          <Button
            class="mt-6 w-full sm:w-fit"
            :icon="
              track.progress.ready
                ? 'i-lucide-settings-2'
                : 'i-lucide-arrow-right'
            "
            :variant="track.progress.ready ? 'outline' : 'solid'"
            :color="track.progress.ready ? 'slate' : 'blue'"
            :label="actionLabel(track.progress, track.key)"
            :trailing-icon="!track.progress.ready"
            @click="openTrack(track.key)"
          />
        </article>
      </div>

      <p v-else class="py-16 text-sm text-n-slate-11">
        {{ t('AI_SETUP.UNAVAILABLE') }}
      </p>
    </template>
  </SettingsLayout>
</template>
