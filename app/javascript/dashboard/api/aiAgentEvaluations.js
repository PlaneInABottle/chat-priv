/* global axios */
import ApiClient from './ApiClient';

class AiAgentEvaluationsAPI extends ApiClient {
  constructor(aiAgentId) {
    super(`ai_agents/${aiAgentId}/evaluation_cases`, {
      accountScoped: true,
    });
    this.runsUrl = `${this.baseUrl()}/ai_agents/${aiAgentId}/evaluation_runs`;
  }

  updateCase(id, data) {
    return axios.patch(`${this.url}/${id}`, data);
  }

  deleteCase(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  generateCases() {
    return axios.post(`${this.url}/generate`);
  }

  getGeneration() {
    return axios.get(`${this.url}/generation`);
  }

  getRuns() {
    return axios.get(this.runsUrl);
  }

  getRun(id) {
    return axios.get(`${this.runsUrl}/${id}`);
  }

  createRun() {
    return axios.post(this.runsUrl);
  }
}

export default AiAgentEvaluationsAPI;
