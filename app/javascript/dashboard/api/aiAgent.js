/* global axios */
import ApiClient from './ApiClient';

class AiAgentAPI extends ApiClient {
  constructor() {
    super('ai_agents', { accountScoped: true });
  }

  getUsage() {
    return axios.get(`${this.baseUrl()}/ai_agent_usage`);
  }

  publish(id) {
    return axios.post(`${this.url}/${id}/publish`);
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }
}

export default new AiAgentAPI();
