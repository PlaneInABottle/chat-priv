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
import AiAgentUsageSummary from './components/AiAgentUsageSummary.vue';

const store = useStore();
const { t } = useI18n();
const router = useRouter();

const agents = useMapGetter('aiAgent/getAiAgents');
const usage = useMapGetter('aiAgent/getUsage');
const uiFlags = useMapGetter('aiAgent/getUIFlags');

const deleteDialogRef = ref(null);
const agentToDelete = ref(null);
const isDeleting = ref(false);

const hasAgents = computed(() => agents.value.length > 0);

onMounted(() => {
  store.dispatch('aiAgent/get');
  store.dispatch('aiAgent/getUsage');
});

const navigateToNew = () => {
  router.push({ name: 'ai_agent_new' });
};

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
  } catch {
    useAlert(t('AI_AGENTS.ITEM.DELETE_ERROR'));
  } finally {
    isDeleting.value = false;
    agentToDelete.value = null;
    deleteDialogRef.value?.close();
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
        <AiAgentUsageSummary :usage="usage" />
        <div
          v-if="hasAgents"
          class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4"
        >
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
