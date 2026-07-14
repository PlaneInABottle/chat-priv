import ApiClient from './ApiClient';

class AiAgentOnboardingAPI extends ApiClient {
  constructor() {
    super('ai_agent_onboarding', { accountScoped: true });
  }
}

export default new AiAgentOnboardingAPI();
