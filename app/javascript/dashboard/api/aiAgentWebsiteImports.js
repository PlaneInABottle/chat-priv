/* global axios */
import ApiClient from './ApiClient';

class AiAgentWebsiteImportsAPI extends ApiClient {
  constructor(aiAgentId) {
    super(`ai_agents/${aiAgentId}/website_imports`, {
      accountScoped: true,
    });
  }

  applyImport(id, data) {
    return axios.post(`${this.url}/${id}/apply`, data);
  }
}

export default AiAgentWebsiteImportsAPI;
