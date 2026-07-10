/* global axios */
import ApiClient from './ApiClient';

class AiAgentTestConversationsAPI extends ApiClient {
  constructor(aiAgentId) {
    super(`ai_agents/${aiAgentId}/test_conversations`, { accountScoped: true });
  }

  clearAll() {
    return axios.delete(`${this.url}/clear_all`);
  }

  sendMessage(id, content, draftInstructions) {
    return axios.post(`${this.url}/${id}/send_message`, {
      content,
      ...(draftInstructions ? { draft_instructions: draftInstructions } : {}),
    });
  }
}

export default AiAgentTestConversationsAPI;
