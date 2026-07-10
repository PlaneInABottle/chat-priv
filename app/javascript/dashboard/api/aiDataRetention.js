/* global axios */
import ApiClient from './ApiClient';

class AiDataRetentionAPI extends ApiClient {
  constructor() {
    super('ai_data_retention', { accountScoped: true });
  }

  updatePolicy(kind, days) {
    return axios.patch(this.url, { kind, days });
  }

  purge(kind) {
    return axios.post(`${this.url}/purge`, { kind });
  }
}

export default new AiDataRetentionAPI();
