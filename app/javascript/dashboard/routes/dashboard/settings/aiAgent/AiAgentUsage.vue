<script setup>
import { onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AiAgentUsageSummary from './components/AiAgentUsageSummary.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const usage = useMapGetter('aiAgent/getUsage');
const usageError = useMapGetter('aiAgent/getUsageError');
const uiFlags = useMapGetter('aiAgent/getUIFlags');

onMounted(() => store.dispatch('aiAgent/getUsage'));
</script>

<template>
  <SettingsLayout :is-loading="uiFlags.isFetchingUsage">
    <template #header>
      <BaseSettingsHeader
        :title="t('AI_ASSISTANT.USAGE.TITLE')"
        :description="t('AI_ASSISTANT.USAGE.DESCRIPTION')"
      >
        <template #actions>
          <Button
            icon="i-lucide-arrow-left"
            color="slate"
            variant="outline"
            :label="t('AI_ASSISTANT.USAGE.BACK')"
            @click="router.push({ name: 'ai_agents' })"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <AiAgentUsageSummary :usage="usage" :has-error="usageError" />
    </template>
  </SettingsLayout>
</template>
