<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const store = useStore();
const { t } = useI18n();
const router = useRouter();

const uiFlags = useMapGetter('aiAgent/getUIFlags');

const name = ref('');
const errorMessage = ref('');

const handleSubmit = async () => {
  errorMessage.value = '';
  if (!name.value.trim()) {
    errorMessage.value = t('AI_AGENTS.NEW.NAME_REQUIRED');
    return;
  }

  const result = await store.dispatch('aiAgent/create', {
    name: name.value.trim(),
  });

  if (result && result.id) {
    useAlert(t('AI_AGENTS.NEW.SUCCESS'));
    router.push({
      name: 'ai_agent_detail',
      params: { id: result.id },
    });
  } else {
    errorMessage.value = t('AI_AGENTS.NEW.ERROR');
  }
};

const handleCancel = () => {
  router.push({ name: 'ai_agents' });
};
</script>

<template>
  <SettingsLayout :is-loading="uiFlags.isCreating">
    <template #header>
      <BaseSettingsHeader
        :title="t('AI_AGENTS.NEW.TITLE')"
        feature-name="ai_agent"
      />
    </template>
    <template #body>
      <form class="flex flex-col gap-6 max-w-xl" @submit.prevent="handleSubmit">
        <woot-input
          v-model="name"
          :label="t('AI_AGENTS.NEW.NAME_LABEL')"
          :placeholder="t('AI_AGENTS.NEW.NAME_PLACEHOLDER')"
          :error="errorMessage"
          @input="errorMessage = ''"
        />
        <div class="flex items-center gap-3">
          <woot-button
            type="submit"
            variant="solid"
            color="blue"
            :is-loading="uiFlags.isCreating"
          >
            {{ t('AI_AGENTS.NEW.CREATE') }}
          </woot-button>
          <woot-button type="button" variant="clear" @click="handleCancel">
            {{ t('AI_AGENTS.NEW.CANCEL') }}
          </woot-button>
        </div>
      </form>
    </template>
  </SettingsLayout>
</template>
