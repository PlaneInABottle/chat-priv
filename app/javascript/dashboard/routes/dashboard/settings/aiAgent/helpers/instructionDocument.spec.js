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
      version: 3,
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

    expect(document.version).toBe(3);
    expect(document.sections.identity).toBe('**Help**');
    expect(document.sections).not.toHaveProperty('unknown');
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
    expect(prompt).toContain('## Rules and boundaries\n\nNever invent prices.');
    expect(prompt).not.toContain('## Identity and purpose');
    expect(instructionContentLength(document)).toBe(prompt.length);
  });
});
