import ApiClient from './ApiClient';

class AiKnowledgeSourcesAPI extends ApiClient {
  constructor() {
    super('ai_knowledge_sources', { accountScoped: true });
  }
}

export default new AiKnowledgeSourcesAPI();
