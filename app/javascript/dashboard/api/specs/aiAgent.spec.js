import aiAgentAPI from '../aiAgent';
import ApiClient from '../ApiClient';

describe('#AiAgentAPI', () => {
  it('creates correct instance', () => {
    expect(aiAgentAPI).toBeInstanceOf(ApiClient);
    expect(aiAgentAPI).toHaveProperty('get');
    expect(aiAgentAPI).toHaveProperty('show');
    expect(aiAgentAPI).toHaveProperty('create');
    expect(aiAgentAPI).toHaveProperty('update');
    expect(aiAgentAPI).toHaveProperty('delete');
  });
});
