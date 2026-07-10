/* global axios */
import ApiClient from './ApiClient';

class AiAgentLearningSuggestionsAPI extends ApiClient {
  constructor(aiAgentId) {
    super(`ai_agents/${aiAgentId}/learning_suggestions`, {
      accountScoped: true,
    });
  }

  applySuggestion(id, data) {
    return axios.post(`${this.url}/${id}/apply`, data);
  }

  dismissSuggestion(id) {
    return axios.post(`${this.url}/${id}/dismiss`);
  }
}

export default AiAgentLearningSuggestionsAPI;
