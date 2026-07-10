import {
  createDefaultInstructionDocument,
  hasInstructionContent,
  instructionDocumentForAgent,
  normalizeInstructionDocument,
} from './instructionDocument';

describe('instructionDocument', () => {
  it('creates the guided standard sections for new assistants', () => {
    const document = createDefaultInstructionDocument();

    expect(document.sections.map(section => section.key)).toEqual([
      'identity',
      'business_context',
      'tasks',
      'rules',
      'handoff',
      'examples',
    ]);
    expect(
      document.sections.find(section => section.key === 'rules').critical
    ).toBe(true);
  });

  it('preserves a legacy prompt as one editable section', () => {
    const document = instructionDocumentForAgent({
      prompt: 'Existing instructions',
      config: {},
    });

    expect(document.sections).toEqual([
      expect.objectContaining({
        key: 'current_instructions',
        content: 'Existing instructions',
      }),
    ]);
  });

  it('normalizes saved profile defaults without losing rich section content', () => {
    const document = normalizeInstructionDocument({
      profile: { language: 'tr' },
      sections: [{ key: 'identity', content: '<strong>Help</strong>' }],
    });

    expect(document.profile).toMatchObject({
      language: 'tr',
      tone: 'natural',
    });
    expect(document.sections[0].content).toBe('<strong>Help</strong>');
    expect(hasInstructionContent(document)).toBe(true);
  });
});
