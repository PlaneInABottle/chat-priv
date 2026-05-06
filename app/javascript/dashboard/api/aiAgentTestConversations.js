/* global axios */
import ApiClient from './ApiClient';

class AiAgentTestConversationsAPI extends ApiClient {
  constructor(aiAgentId) {
    super(`ai_agents/${aiAgentId}/test_conversations`, { accountScoped: true });
  }

  clearAll() {
    return axios.delete(`${this.url}/clear_all`);
  }

  sendMessage(id, content) {
    return axios.post(`${this.url}/${id}/send_message`, { content });
  }
}

export default AiAgentTestConversationsAPI;
