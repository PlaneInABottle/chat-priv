<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AiAgentListItem from './AiAgentListItem.vue';

const store = useStore();
const { t } = useI18n();
const router = useRouter();

const agents = useMapGetter('aiAgent/getAiAgents');
const uiFlags = useMapGetter('aiAgent/getUIFlags');

const deleteDialogRef = ref(null);
const agentToDelete = ref(null);
const isDeleting = ref(false);

const hasAgents = computed(() => agents.value.length > 0);

onMounted(() => {
  store.dispatch('aiAgent/get');
});

const navigateToNew = () => {
  router.push({ name: 'ai_agent_new' });
};

const navigateToUsage = () => router.push({ name: 'ai_agent_usage' });
const navigateToDataPrivacy = () =>
  router.push({ name: 'ai_agent_data_privacy' });

const openDeleteDialog = agent => {
  agentToDelete.value = agent;
  deleteDialogRef.value?.open();
};

const confirmDelete = async () => {
  if (!agentToDelete.value) return;
  isDeleting.value = true;
  try {
    await store.dispatch('aiAgent/delete', agentToDelete.value.id);
    useAlert(t('AI_AGENTS.ITEM.DELETE_SUCCESS'));
    agentToDelete.value = null;
    deleteDialogRef.value?.close();
  } catch {
    useAlert(t('AI_AGENTS.ITEM.DELETE_ERROR'));
  } finally {
    isDeleting.value = false;
  }
};
</script>

<template>
  <SettingsLayout :is-loading="uiFlags.isFetching">
    <template #header>
      <BaseSettingsHeader
        :title="t('AI_AGENTS.HEADER')"
        :description="t('AI_AGENTS.DESCRIPTION')"
        feature-name="ai_agent"
      >
        <template #actions>
          <Button
            icon="i-lucide-circle-plus"
            :label="t('AI_AGENTS.ADD')"
            @click="navigateToNew"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="flex flex-col gap-6">
        <div class="flex flex-wrap justify-end gap-2">
          <Button
            icon="i-lucide-shield-check"
            variant="outline"
            color="slate"
            :label="t('AI_DATA_RETENTION.OPEN')"
            @click="navigateToDataPrivacy"
          />
          <Button
            icon="i-lucide-chart-no-axes-column"
            variant="outline"
            color="slate"
            :label="t('AI_ASSISTANT.USAGE.OPEN')"
            @click="navigateToUsage"
          />
        </div>
        <div
          v-if="hasAgents"
          class="overflow-hidden rounded-lg border border-n-weak bg-n-alpha-1"
        >
          <div
            class="hidden grid-cols-[minmax(0,1fr)_120px_140px_140px_auto] gap-3 border-b border-n-weak bg-n-alpha-2 px-4 py-2 text-xs font-medium text-n-slate-11 md:grid"
          >
            <span>{{ t('AI_ASSISTANT.LIST.NAME') }}</span>
            <span>{{ t('AI_ASSISTANT.LIST.STATUS') }}</span>
            <span>{{ t('AI_ASSISTANT.LIST.INBOXES') }}</span>
            <span>{{ t('AI_ASSISTANT.LIST.UPDATED') }}</span>
            <span class="sr-only">{{ t('AI_ASSISTANT.LIST.ACTIONS') }}</span>
          </div>
          <AiAgentListItem
            v-for="agent in agents"
            :key="agent.id"
            :agent="agent"
            @delete="openDeleteDialog"
          />
        </div>
        <div
          v-else
          class="flex flex-col items-center justify-center py-20 gap-4"
        >
          <p class="text-n-slate-12 text-base">
            {{ t('AI_AGENTS.LIST.EMPTY_DESCRIPTION') }}
          </p>
          <Button
            icon="i-lucide-circle-plus"
            :label="t('AI_AGENTS.LIST.CREATE_FIRST')"
            @click="navigateToNew"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>

  <Dialog
    ref="deleteDialogRef"
    type="alert"
    :title="t('AI_AGENTS.ITEM.DELETE_CONFIRM')"
    :confirm-button-label="t('AI_AGENTS.ITEM.DELETE')"
    :cancel-button-label="t('AI_AGENTS.NEW.CANCEL')"
    :is-loading="isDeleting"
    @confirm="confirmDelete"
  />
</template>
