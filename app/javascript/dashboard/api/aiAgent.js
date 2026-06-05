/* global axios */
import ApiClient from './ApiClient';

class AiAgentAPI extends ApiClient {
  constructor() {
    super('ai_agents', { accountScoped: true });
  }

  getToolExecutions(id, params = {}) {
    return axios.get(`${this.url}/${id}/tool_executions`, { params });
  }

  getUsage() {
    return axios.get(`${this.baseUrl()}/ai_agent_usage`);
  }
}

export default new AiAgentAPI();
