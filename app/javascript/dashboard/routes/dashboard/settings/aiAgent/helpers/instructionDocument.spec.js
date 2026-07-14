import {
  compileInstructionDocument,
  createDefaultInstructionDocument,
  hasInstructionContent,
  instructionContentLength,
  instructionDocumentForAgent,
  normalizeInstructionDocument,
} from './instructionDocument';

describe('instructionDocument', () => {
  it('creates one guided document with fixed sections', () => {
    const document = createDefaultInstructionDocument();

    expect(document).toMatchObject({
      version: 4,
      locale: 'tr',
      profile: { tone: 'natural' },
    });
    expect(document.sections).toMatchObject({
      identity: '',
      rules: '',
      additional: '',
    });
    expect(document).not.toHaveProperty('content');
  });

  it('presents a legacy prompt in the default document without claiming profile settings', () => {
    const document = instructionDocumentForAgent({
      prompt: 'Existing instructions',
      config: {},
    });

    expect(document.profile).toEqual({
      language: 'not_set',
      tone: 'not_set',
      formality: 'not_set',
      response_length: 'not_set',
    });
    expect(document.sections.additional).toBe('Existing instructions');
    expect(document.sections.identity).toBe('');
  });

  it('normalizes supported fixed section keys and drops unknown keys', () => {
    const document = normalizeInstructionDocument({
      profile: { language: 'tr' },
      sections: { identity: '**Help**', unknown: 'Ignore' },
    });

    expect(document.version).toBe(4);
    expect(document.locale).toBe('tr');
    expect(document.sections.identity).toBe('**Help**');
    expect(document.sections).not.toHaveProperty('unknown');
  });

  it('collapses the legacy warm tone into friendly', () => {
    const document = normalizeInstructionDocument({
      profile: { tone: 'warm' },
    });

    expect(document.profile.tone).toBe('friendly');
  });

  it('detects section content and compiles only configured sections', () => {
    const document = normalizeInstructionDocument();
    expect(hasInstructionContent(document)).toBe(false);
    expect(hasInstructionContent(createDefaultInstructionDocument())).toBe(
      true
    );

    document.sections.rules = 'Never invent prices.';
    const prompt = compileInstructionDocument(document);

    expect(hasInstructionContent(document)).toBe(true);
    expect(prompt).toContain('## Kurallar ve sınırlar\n\nNever invent prices.');
    expect(prompt).not.toContain('## Kimlik ve amaç');
    expect(instructionContentLength(document)).toBe(prompt.length);
  });

  it('keeps version three documents without a language in English', () => {
    const document = normalizeInstructionDocument({
      version: 3,
      sections: { rules: 'Keep this.' },
    });

    expect(document.locale).toBe('en');
    expect(compileInstructionDocument(document)).toContain(
      '## Rules and boundaries'
    );
  });
});
