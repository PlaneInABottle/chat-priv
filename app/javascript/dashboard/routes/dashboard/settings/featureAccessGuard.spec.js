import { redirectIfFeatureDisabled } from './featureAccessGuard';
import store from '../../../store';

vi.mock('../../../store', () => ({
  default: {
    dispatch: vi.fn(),
    getters: {
      'accounts/getAccount': vi.fn(),
      'accounts/isFeatureEnabledonAccount': vi.fn(),
    },
  },
}));

describe('redirectIfFeatureDisabled', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    store.getters['accounts/getAccount'].mockReturnValue({ id: 1 });
  });

  it('allows routes without feature metadata', async () => {
    const result = await redirectIfFeatureDisabled({
      meta: {},
      params: { accountId: '1' },
    });

    expect(result).toBe(true);
  });

  it('keeps existing single feature flag behavior', async () => {
    store.getters['accounts/isFeatureEnabledonAccount'].mockReturnValue(true);

    const result = await redirectIfFeatureDisabled({
      meta: { featureFlag: 'ai_agent' },
      params: { accountId: '1' },
    });

    expect(result).toBe(true);
    const featureEnabled = store.getters['accounts/isFeatureEnabledonAccount'];
    expect(featureEnabled).toHaveBeenCalledWith(1, 'ai_agent');
  });

  it('requires every feature in featureFlags', async () => {
    store.getters['accounts/isFeatureEnabledonAccount'].mockImplementation(
      (_accountId, feature) => feature === 'integrations'
    );

    const result = await redirectIfFeatureDisabled({
      meta: { featureFlags: ['integrations', 'ikas_integration'] },
      params: { accountId: '1' },
    });

    expect(result).toEqual({
      name: 'settings_home',
      params: { accountId: '1' },
    });
  });

  it('fetches the account before checking feature access when missing locally', async () => {
    store.getters['accounts/getAccount'].mockReturnValue({});
    store.getters['accounts/isFeatureEnabledonAccount'].mockReturnValue(true);

    const result = await redirectIfFeatureDisabled({
      meta: { featureFlag: 'voice_ai' },
      params: { accountId: '1' },
    });

    expect(result).toBe(true);
    expect(store.dispatch).toHaveBeenCalledWith('accounts/get', {
      silent: true,
    });
  });
});
