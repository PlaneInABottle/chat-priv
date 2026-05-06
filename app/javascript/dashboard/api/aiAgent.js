import ApiClient from './ApiClient';

class AiAgentAPI extends ApiClient {
  constructor() {
    super('ai_agents', { accountScoped: true });
  }
}

export default new AiAgentAPI();
