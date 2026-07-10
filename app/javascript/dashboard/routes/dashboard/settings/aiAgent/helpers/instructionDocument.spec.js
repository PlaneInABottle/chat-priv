import {
  createDefaultInstructionDocument,
  createInstructionContent,
  hasInstructionContent,
  instructionDocumentForAgent,
  normalizeInstructionDocument,
} from './instructionDocument';

describe('instructionDocument', () => {
  it('creates one guided document with heading-based sections', () => {
    const document = createDefaultInstructionDocument();

    expect(document).toMatchObject({
      version: 2,
      profile: { tone: 'natural' },
    });
    expect(document.content).toContain('## Identity and purpose');
    expect(document.content).toContain('## Rules and boundaries');
    expect(document).not.toHaveProperty('sections');
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
    expect(document.content).toContain('## General instructions');
    expect(document.content).toContain('Existing instructions');
    expect(document.content).toContain('## Human handoff');
  });

  it('converts saved version one sections into a continuous document', () => {
    const document = normalizeInstructionDocument({
      profile: { language: 'tr' },
      sections: [{ key: 'identity', content: '<p><strong>Help</strong></p>' }],
    });

    expect(document.version).toBe(2);
    expect(document.content).toBe('## Identity and purpose\n\n**Help**');
    expect(document).not.toHaveProperty('sections');
  });

  it('detects body content separately from empty template headings', () => {
    expect(hasInstructionContent({ content: createInstructionContent() })).toBe(
      false
    );
    expect(
      hasInstructionContent({
        content: createInstructionContent({ rules: 'Never invent prices.' }),
      })
    ).toBe(true);
  });
});
