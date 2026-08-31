import {
  compileVoiceInstructionDocument,
  normalizeVoiceInstructionDocument,
  voiceInstructionContentLength,
  voiceInstructionDocumentFromLegacy,
} from './voiceInstructionDocument';
import parityCases from '../../../../../../../../spec/fixtures/voice_instruction_documents.json';

const document = locale =>
  parityCases.find(testCase => testCase.locale === locale).document;

describe('voiceInstructionDocument', () => {
  it('returns the exact canonical key order and deterministic request shape', () => {
    const normalized = normalizeVoiceInstructionDocument(document('en'));

    expect(Object.keys(normalized)).toEqual([
      'version',
      'locale',
      'profile',
      'sections',
    ]);
    expect(Object.keys(normalized.profile)).toEqual([
      'language',
      'tone',
      'formality',
      'response_length',
    ]);
    expect(Object.keys(normalized.sections)).toEqual([
      'business_context',
      'tasks',
      'rules',
    ]);
    expect(JSON.stringify(normalized)).toBe(
      JSON.stringify(normalizeVoiceInstructionDocument(normalized))
    );
  });

  it.each([
    [{ ...document('en'), extra: true }],
    [{ ...document('en'), version: 3 }],
    [{ ...document('en'), locale: 'de' }],
    [
      {
        ...document('en'),
        profile: { ...document('en').profile, identity: 'x' },
      },
    ],
    [
      {
        ...document('en'),
        sections: { ...document('en').sections, handoff: 'x' },
      },
    ],
    [{ ...document('en'), sections: { ...document('en').sections, rules: 4 } }],
  ])('rejects malformed or unknown input', invalid => {
    expect(() => normalizeVoiceInstructionDocument(invalid)).toThrow(TypeError);
  });

  it('projects the exact legacy prompt into rules only', () => {
    const legacy = voiceInstructionDocumentFromLegacy('Exact <body>\nLine 2');
    expect(legacy.sections).toEqual({
      business_context: '',
      tasks: '',
      rules: 'Exact <body>\nLine 2',
    });
  });

  it.each(parityCases)(
    'compiles $locale profile and Voice sections to shared canonical bytes',
    testCase => {
      const compiled = compileVoiceInstructionDocument(testCase.document);
      expect(compiled).toBe(testCase.compiled);
      expect(voiceInstructionContentLength(testCase.document)).toBe(
        Array.from(compiled).length
      );
    }
  );

  it('counts astral Unicode like Ruby and enforces the 50,000-character boundary', () => {
    const withRules = rules => ({
      ...document('en'),
      profile: {
        language: 'not_set',
        tone: 'not_set',
        formality: 'not_set',
        response_length: 'not_set',
      },
      sections: { business_context: '', tasks: '', rules },
    });
    const headingLength = voiceInstructionContentLength(withRules('x')) - 1;
    const exact = withRules('😀'.repeat(50000 - headingLength));
    const over = withRules(`${exact.sections.rules}😀`);

    expect(voiceInstructionContentLength(exact)).toBe(50000);
    expect(compileVoiceInstructionDocument(exact).length).toBeGreaterThan(
      50000
    );
    expect(voiceInstructionContentLength(over)).toBe(50001);
  });
});
