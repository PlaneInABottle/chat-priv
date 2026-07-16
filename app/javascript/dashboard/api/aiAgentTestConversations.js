/* global axios */
import ApiClient from './ApiClient';

class AiAgentTestConversationsAPI extends ApiClient {
  constructor(aiAgentId) {
    super(`ai_agents/${aiAgentId}/test_conversations`, { accountScoped: true });
  }

  clearAll() {
    return axios.delete(`${this.url}/clear_all`);
  }

  sendMessage(id, content, draftInstructions, selection = {}) {
    return axios.post(`${this.url}/${id}/send_message`, {
      content,
      ...(selection.replyToMessageId
        ? {
            reply_to_message_id: selection.replyToMessageId,
            selected_value: selection.selectedValue,
          }
        : {}),
      ...(draftInstructions ? { draft_instructions: draftInstructions } : {}),
    });
  }
}

export default AiAgentTestConversationsAPI;
