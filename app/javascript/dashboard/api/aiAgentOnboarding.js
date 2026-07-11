/* global axios */
import ApiClient from './ApiClient';

class AiAgentOnboardingAPI extends ApiClient {
  constructor() {
    super('ai_agent_onboarding', { accountScoped: true });
  }

  complete() {
    return axios.post(`${this.url}/complete`);
  }
}

export default new AiAgentOnboardingAPI();
