/* global axios */
import ApiClient from './ApiClient';

class AiKnowledgeSourcesAPI extends ApiClient {
  constructor() {
    super('ai_knowledge_sources', { accountScoped: true });
  }

  sync(id) {
    return axios.post(`${this.url}/${id}/sync`);
  }
}

export default new AiKnowledgeSourcesAPI();
