<script setup>
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import AiDataRetentionPanel from '../components/AiDataRetentionPanel.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';

const router = useRouter();
const { t } = useI18n();
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        :title="t('AI_DATA_RETENTION.PAGE_TITLE')"
        :description="t('AI_DATA_RETENTION.PAGE_DESCRIPTION')"
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
      <AiDataRetentionPanel kind="text" />
    </template>
  </SettingsLayout>
</template>
