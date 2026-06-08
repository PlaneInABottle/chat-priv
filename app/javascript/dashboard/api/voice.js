/* global axios */
import ApiClient from './ApiClient';

class VoiceAPI extends ApiClient {
  constructor() {
    super('voice', { accountScoped: true });
  }

  getSettings() {
    return axios.get(`${this.url}/inbox_settings`);
  }

  createSetting(data) {
    return axios.post(`${this.url}/inbox_settings`, data);
  }

  updateSetting(id, data) {
    return axios.patch(`${this.url}/inbox_settings/${id}`, data);
  }

  createTestCall(data) {
    return axios.post(`${this.url}/test_calls`, data);
  }

  getCall(id) {
    return axios.get(`${this.url}/calls/${id}`);
  }

  createToken(id, data) {
    return axios.post(`${this.url}/calls/${id}/token`, data);
  }

  takeOver(id) {
    return axios.post(`${this.url}/calls/${id}/take_over`);
  }

  endCall(id, data = {}) {
    return axios.post(`${this.url}/calls/${id}/end`, data);
  }
}

export default new VoiceAPI();
