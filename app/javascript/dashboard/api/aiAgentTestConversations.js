/* global axios */
import ApiClient from './ApiClient';

class AiAgentTestConversationsAPI extends ApiClient {
  constructor() {
    super('ai_agent_test_conversations', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create() {
    return axios.post(this.url, {});
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  clearAll() {
    return axios.delete(`${this.url}/clear_all`);
  }

  sendMessage(id, content) {
    return axios.post(`${this.url}/${id}/send_message`, { content });
  }
}

export default new AiAgentTestConversationsAPI();
