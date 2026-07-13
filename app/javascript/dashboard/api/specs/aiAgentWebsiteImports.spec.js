import AiAgentWebsiteImportsAPI from '../aiAgentWebsiteImports';
import ApiClient from '../ApiClient';

describe('#AiAgentWebsiteImportsAPI', () => {
  it('exposes preview and selective-apply operations for an assistant', () => {
    const api = new AiAgentWebsiteImportsAPI(42);

    expect(api).toBeInstanceOf(ApiClient);
    expect(api.resource).toBe('ai_agents/42/website_imports');
    expect(api).toHaveProperty('get');
    expect(api).toHaveProperty('show');
    expect(api).toHaveProperty('create');
    expect(api).toHaveProperty('applyImport');
  });
});
