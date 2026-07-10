export const PROFILE_DEFAULTS = {
  language: 'not_set',
  tone: 'not_set',
  formality: 'not_set',
  response_length: 'not_set',
};

export const NEW_ASSISTANT_PROFILE_DEFAULTS = {
  language: 'same_as_customer',
  tone: 'natural',
  formality: 'balanced',
  response_length: 'balanced',
};

export const INSTRUCTION_SECTION_KEYS = [
  'identity',
  'business_context',
  'tasks',
  'rules',
  'handoff',
  'examples',
  'additional',
];

export const INSTRUCTION_SECTION_TITLES = {
  identity: 'Identity and purpose',
  business_context: 'Business context',
  tasks: 'Tasks and conversation flow',
  rules: 'Rules and boundaries',
  handoff: 'Human handoff',
  examples: 'Example conversations',
  additional: 'Additional instructions',
};

const PROFILE_FIELD_NAMES = {
  language: 'Reply language',
  tone: 'Tone',
  formality: 'Formality',
  response_length: 'Response length',
};

const PROFILE_PROMPT_LABELS = {
  language: {
    same_as_customer: "Use the customer's language",
    tr: 'Turkish',
    en: 'English',
  },
  tone: {
    natural: 'Natural',
    friendly: 'Friendly',
    professional: 'Professional',
    warm: 'Warm',
    concise: 'Concise',
  },
  formality: { balanced: 'Balanced', casual: 'Casual', formal: 'Formal' },
  response_length: {
    balanced: 'Balanced',
    short: 'Short',
    detailed: 'Detailed',
  },
};

const normalizeText = value => String(value || '').trim();

const emptySections = () =>
  Object.fromEntries(INSTRUCTION_SECTION_KEYS.map(key => [key, '']));

export const createDefaultInstructionDocument = () => ({
  version: 3,
  profile: { ...NEW_ASSISTANT_PROFILE_DEFAULTS },
  sections: emptySections(),
});

export const normalizeInstructionDocument = document => {
  const source = document || {};
  const profile = source.profile || {};
  const sections = source.sections || {};

  return {
    version: 3,
    profile: {
      language: profile.language || PROFILE_DEFAULTS.language,
      tone: profile.tone || PROFILE_DEFAULTS.tone,
      formality: profile.formality || PROFILE_DEFAULTS.formality,
      response_length:
        profile.response_length || PROFILE_DEFAULTS.response_length,
    },
    sections: Object.fromEntries(
      INSTRUCTION_SECTION_KEYS.map(key => [key, sections[key] || ''])
    ),
  };
};

export const instructionDocumentForAgent = agent => {
  const savedDocument = agent?.config?.instructions;
  if (savedDocument) return normalizeInstructionDocument(savedDocument);

  return {
    version: 3,
    profile: { ...PROFILE_DEFAULTS },
    sections: { ...emptySections(), additional: normalizeText(agent?.prompt) },
  };
};

export const hasInstructionContent = document => {
  const { profile, sections } = normalizeInstructionDocument(document);
  const hasProfilePreference = Object.values(profile).some(
    value => value !== 'not_set'
  );
  return (
    hasProfilePreference ||
    Object.values(sections).some(value => normalizeText(value))
  );
};

export const compileInstructionDocument = document => {
  const normalized = normalizeInstructionDocument(document);
  const profileLines = Object.entries(PROFILE_PROMPT_LABELS)
    .map(([key, labels]) => {
      const label = labels[normalized.profile[key]];
      return label ? `- ${PROFILE_FIELD_NAMES[key]}: ${label}` : '';
    })
    .filter(Boolean);
  const profilePrompt = profileLines.length
    ? `## Language and tone\n${profileLines.join('\n')}`
    : '';
  const sectionPrompts = INSTRUCTION_SECTION_KEYS.map(key => {
    const content = normalizeText(normalized.sections[key]);
    return content ? `## ${INSTRUCTION_SECTION_TITLES[key]}\n\n${content}` : '';
  }).filter(Boolean);

  return [profilePrompt, ...sectionPrompts].filter(Boolean).join('\n\n');
};

export const instructionContentLength = document =>
  compileInstructionDocument(document).length;
