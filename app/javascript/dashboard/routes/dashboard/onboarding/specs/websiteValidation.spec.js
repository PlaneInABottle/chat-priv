import { normalizeWebsiteInput } from '../websiteValidation';

describe('normalizeWebsiteInput', () => {
  it('normalizes a public domain and preserves a valid path', () => {
    expect(normalizeWebsiteInput(' example.com/about#team ')).toBe(
      'https://example.com/about'
    );
  });

  it.each([
    'randomvalue',
    'hello world',
    'http://127.0.0.1',
    'https://93.184.216.34',
    'user:pass@example.com',
  ])('rejects %s as a company website', value => {
    expect(normalizeWebsiteInput(value)).toBeNull();
  });

  it('allows an empty optional website', () => {
    expect(normalizeWebsiteInput('  ')).toBe('');
  });
});
