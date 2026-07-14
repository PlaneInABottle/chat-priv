/* global axios */
import ApiClient from './ApiClient';

class AiAgentOnboardingAPI extends ApiClient {
  constructor() {
    super('ai_agent_onboarding', { accountScoped: true });
  }

  verifyWebsite(data) {
    return axios.post(`${this.url}/verify_website`, data);
  }
}

export default new AiAgentOnboardingAPI();
