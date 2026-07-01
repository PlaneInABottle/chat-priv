import store from '../../../store';

export const redirectIfFeatureDisabled = async to => {
  const { featureFlag, featureFlags } = to.meta || {};
  const requiredFlags = featureFlags || (featureFlag ? [featureFlag] : []);
  if (!requiredFlags.length) return true;

  const accountId = Number(to.params.accountId);
  const account = store.getters['accounts/getAccount'](accountId);

  if (!account?.id) {
    await store.dispatch('accounts/get', { silent: true });
  }

  if (
    requiredFlags.every(flag =>
      store.getters['accounts/isFeatureEnabledonAccount'](accountId, flag)
    )
  ) {
    return true;
  }

  return { name: 'settings_home', params: to.params };
};
