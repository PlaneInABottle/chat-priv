/* global axios */
import ApiClient from './ApiClient';

class AiAgentAPI extends ApiClient {
  constructor() {
    super('ai_agent', { accountScoped: true });
  }

  update(data) {
    return axios.patch(this.url, data);
  }

  simulate({ messages }) {
    return axios.post(`${this.url}/simulate`, { messages });
  }
}

export default new AiAgentAPI();
