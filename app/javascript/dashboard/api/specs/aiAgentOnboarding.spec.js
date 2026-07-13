import aiAgentOnboardingAPI from '../aiAgentOnboarding';
import ApiClient from '../ApiClient';

describe('#AiAgentOnboardingAPI', () => {
  it('exposes the account-scoped onboarding contract', () => {
    expect(aiAgentOnboardingAPI).toBeInstanceOf(ApiClient);
    expect(aiAgentOnboardingAPI).toHaveProperty('get');
    expect(aiAgentOnboardingAPI).toHaveProperty('create');
    expect(aiAgentOnboardingAPI).toHaveProperty('complete');
  });
});
