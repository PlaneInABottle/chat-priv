import { getHelpUrlForFeature, isChatwootHelpUrl } from '../featureHelper';

describe('featureHelper', () => {
  it('hides Chatwoot-owned help URLs', () => {
    expect(getHelpUrlForFeature('macros')).toBeUndefined();
    expect(isChatwootHelpUrl('https://chwt.app/hc/macros')).toBe(true);
    expect(
      isChatwootHelpUrl('https://developers.chatwoot.com/docs/macros')
    ).toBe(true);
  });

  it('keeps custom help URLs available', () => {
    expect(isChatwootHelpUrl('https://docs.example.com/macros')).toBe(false);
    expect(isChatwootHelpUrl('not-a-url')).toBe(false);
  });
});
