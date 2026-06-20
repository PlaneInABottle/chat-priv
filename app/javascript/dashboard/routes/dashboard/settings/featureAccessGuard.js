import store from '../../../store';

export const redirectIfFeatureDisabled = async to => {
  const { featureFlag } = to.meta || {};
  if (!featureFlag) return true;

  const accountId = Number(to.params.accountId);
  const account = store.getters['accounts/getAccount'](accountId);

  if (!account?.id) {
    await store.dispatch('accounts/get', { silent: true });
  }

  if (
    store.getters['accounts/isFeatureEnabledonAccount'](accountId, featureFlag)
  ) {
    return true;
  }

  return { name: 'settings_home', params: to.params };
};
