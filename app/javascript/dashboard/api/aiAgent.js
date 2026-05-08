import ApiClient from './ApiClient';
import axios from 'axios';

class AiAgentAPI extends ApiClient {
  constructor() {
    super('ai_agents', { accountScoped: true });
  }

  getToolExecutions(id, params = {}) {
    return axios.get(`${this.url}/${id}/tool_executions`, { params });
  }
}

export default new AiAgentAPI();
