<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Integration from './Integration.vue';
import Spinner from 'shared/components/Spinner.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();

const integrationLoaded = ref(false);
const form = ref({
  storeUrl: '',
  clientId: '',
  clientSecret: '',
});
const errorMessage = ref('');

const syncFormWithResponse = response => {
  form.value.storeUrl = response?.store_url || '';
  form.value.clientId = '';
  form.value.clientSecret = '';
};

const integration = computed(() =>
  store.getters['integrations/getIntegration']('ikas', {
    id: 'ikas',
  })
);
const uiFlags = computed(() => store.getters['integrations/getUIFlags']);

const integrationAction = computed(() =>
  integration.value.can_disconnect ? 'disconnect' : 'connect'
);

const isDisabledState = computed(() => integration.value.state === 'disabled');
const isReconnectRequiredState = computed(
  () => integration.value.state === 'reconnect_required'
);
const isConnectedState = computed(
  () => integration.value.state === 'connected'
);
const isSubmitting = computed(
  () => uiFlags.value.isCreatingIkas || uiFlags.value.isUpdatingIkas
);

const initializeIkasIntegration = async () => {
  await store.dispatch('integrations/get');
  const response = await store.dispatch('integrations/showIkas');
  syncFormWithResponse(response);
  integrationLoaded.value = true;
};

const validateForm = () => {
  if (
    !form.value.storeUrl ||
    (!form.value.clientId && !integration.value.client_id_masked)
  ) {
    errorMessage.value = t('INTEGRATION_SETTINGS.IKAS.ERRORS.REQUIRED_FIELDS');
    return false;
  }

  if (!isConnectedState.value && !form.value.clientSecret) {
    errorMessage.value = t('INTEGRATION_SETTINGS.IKAS.ERRORS.REQUIRED_FIELDS');
    return false;
  }

  errorMessage.value = '';
  return true;
};

const submit = async () => {
  if (!validateForm()) return;

  const payload = {
    store_url: form.value.storeUrl,
    client_id: form.value.clientId,
    client_secret: form.value.clientSecret,
  };

  try {
    const response = isConnectedState.value
      ? await store.dispatch('integrations/updateIkas', payload)
      : await store.dispatch('integrations/connectIkas', payload);

    syncFormWithResponse(response);
    useAlert(t('INTEGRATION_SETTINGS.IKAS.SUCCESS'));
  } catch (error) {
    errorMessage.value =
      error?.response?.data?.status_message ||
      t('INTEGRATION_SETTINGS.IKAS.ERRORS.GENERIC');
  }
};

const disconnect = async () => {
  try {
    await store.dispatch('integrations/deleteIkas');
    useAlert(t('INTEGRATION_SETTINGS.DELETE.API.SUCCESS_MESSAGE'));
    errorMessage.value = '';
  } catch (error) {
    useAlert(t('INTEGRATION_SETTINGS.WEBHOOK.DELETE.API.ERROR_MESSAGE'));
  }
};

onMounted(() => {
  initializeIkasIntegration();
});
</script>

<template>
  <div class="flex-grow flex-shrink p-4 overflow-auto max-w-6xl mx-auto">
    <div
      v-if="integrationLoaded && !uiFlags.isFetchingIkas"
      class="flex flex-col gap-6"
    >
      <Integration
        :integration-id="integration.id"
        :integration-logo="integration.logo || 'ikas.svg'"
        :integration-name="integration.name"
        :integration-description="integration.description"
        :integration-enabled="integration.can_disconnect"
        :integration-action="integrationAction"
        :custom-delete-action="disconnect"
        :redirect-after-delete="false"
        :delete-confirmation-text="{
          title: $t('INTEGRATION_SETTINGS.IKAS.DELETE.TITLE'),
          message: $t('INTEGRATION_SETTINGS.IKAS.DELETE.MESSAGE'),
        }"
      >
        <template #action>
          <Button
            teal
            :disabled="isDisabledState"
            :label="$t('INTEGRATION_SETTINGS.CONNECT.BUTTON_TEXT')"
            @click="submit"
          />
        </template>
      </Integration>

      <div
        v-if="isDisabledState || isReconnectRequiredState || errorMessage"
        class="outline outline-1 outline-n-container bg-n-alpha-3 rounded-md p-4"
      >
        <p v-if="isDisabledState" class="text-n-slate-11">
          {{ $t('INTEGRATION_SETTINGS.IKAS.DISABLED') }}
        </p>
        <p v-else-if="isReconnectRequiredState" class="text-n-ruby-9">
          {{ $t('INTEGRATION_SETTINGS.IKAS.RECONNECT_REQUIRED') }}
        </p>
        <p v-if="errorMessage" class="text-n-ruby-9 mt-2">
          {{ errorMessage }}
        </p>
      </div>

      <div
        class="outline outline-1 outline-n-container bg-n-alpha-3 rounded-md p-6 flex flex-col gap-4"
      >
        <Input
          v-model="form.storeUrl"
          :label="$t('INTEGRATION_SETTINGS.IKAS.FORM.STORE_URL.LABEL')"
          :placeholder="
            $t('INTEGRATION_SETTINGS.IKAS.FORM.STORE_URL.PLACEHOLDER')
          "
          :message="$t('INTEGRATION_SETTINGS.IKAS.FORM.STORE_URL.HELP')"
          :disabled="isDisabledState || isSubmitting"
        />
        <Input
          v-model="form.clientId"
          :label="$t('INTEGRATION_SETTINGS.IKAS.FORM.CLIENT_ID.LABEL')"
          :placeholder="
            $t('INTEGRATION_SETTINGS.IKAS.FORM.CLIENT_ID.PLACEHOLDER')
          "
          :message="
            integration.client_id_masked && !form.clientId
              ? $t('INTEGRATION_SETTINGS.IKAS.FORM.CLIENT_ID.HELP_MASKED', {
                  clientId: integration.client_id_masked,
                })
              : $t('INTEGRATION_SETTINGS.IKAS.FORM.CLIENT_ID.HELP')
          "
          :disabled="isDisabledState || isSubmitting"
        />
        <Input
          v-model="form.clientSecret"
          type="password"
          :label="$t('INTEGRATION_SETTINGS.IKAS.FORM.CLIENT_SECRET.LABEL')"
          :placeholder="
            $t('INTEGRATION_SETTINGS.IKAS.FORM.CLIENT_SECRET.PLACEHOLDER')
          "
          :message="
            isConnectedState
              ? $t('INTEGRATION_SETTINGS.IKAS.FORM.CLIENT_SECRET.HELP_OPTIONAL')
              : $t('INTEGRATION_SETTINGS.IKAS.FORM.CLIENT_SECRET.HELP')
          "
          :disabled="isDisabledState || isSubmitting"
        />

        <div v-if="integration.store_host" class="text-sm text-n-slate-11">
          {{
            $t('INTEGRATION_SETTINGS.IKAS.CONNECTED_STORE', {
              storeHost: integration.store_host,
            })
          }}
        </div>

        <div class="text-sm text-n-slate-11">
          {{ $t('INTEGRATION_SETTINGS.IKAS.TOOL_CONTEXT_NOTE') }}
        </div>

        <div class="flex gap-3">
          <Button
            teal
            :is-loading="isSubmitting"
            :disabled="isDisabledState"
            :label="
              isConnectedState
                ? $t('INTEGRATION_SETTINGS.IKAS.UPDATE')
                : $t('INTEGRATION_SETTINGS.IKAS.CONNECT')
            "
            @click="submit"
          />
        </div>
      </div>
    </div>
    <div v-else class="flex items-center justify-center flex-1">
      <Spinner size="" color-scheme="primary" />
    </div>
  </div>
</template>
