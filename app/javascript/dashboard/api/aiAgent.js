/* global axios */
import ApiClient from './ApiClient';

class AiAgentAPI extends ApiClient {
  constructor() {
    super('ai_agents', { accountScoped: true });
  }

  getToolExecutions(id, params = {}) {
    return axios.get(`${this.url}/${id}/tool_executions`, { params });
  }
}

export default new AiAgentAPI();
