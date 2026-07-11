import ApiClient from './ApiClient';

class AiImprovementUsageAPI extends ApiClient {
  constructor() {
    super('ai_improvement_usage', { accountScoped: true });
  }
}

export default new AiImprovementUsageAPI();
