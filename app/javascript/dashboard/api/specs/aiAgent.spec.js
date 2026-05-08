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
    expect(aiAgentAPI).toHaveProperty('getToolExecutions');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      get: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      window.history.pushState({}, '', '/app/accounts/1/settings/ai-agents/1');
    });

    afterEach(() => {
      window.axios = originalAxios;
      window.history.pushState({}, '', '/');
      axiosMock.get.mockClear();
    });

    it('#getToolExecutions uses the authenticated global axios instance', () => {
      const params = { status: 'executed' };

      aiAgentAPI.getToolExecutions(1, params);

      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/ai_agents/1/tool_executions',
        { params }
      );
    });
  });
});
