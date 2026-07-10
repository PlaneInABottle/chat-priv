export const PROFILE_DEFAULTS = {
  language: 'same_as_customer',
  tone: 'natural',
  formality: 'balanced',
  response_length: 'balanced',
};

export const STANDARD_SECTION_KEYS = [
  'identity',
  'business_context',
  'tasks',
  'rules',
  'handoff',
  'examples',
];

const createSection = key => ({
  key,
  title: '',
  content: '',
  critical: key === 'rules',
  custom: false,
});

export const createDefaultInstructionDocument = () => ({
  version: 1,
  profile: { ...PROFILE_DEFAULTS },
  sections: STANDARD_SECTION_KEYS.map(createSection),
});

const normalizeSection = section => ({
  key: section?.key || `custom_${Date.now()}`,
  title: section?.title || '',
  content: section?.content || '',
  critical: Boolean(section?.critical),
  custom: Boolean(section?.custom),
});

export const normalizeInstructionDocument = document => {
  const source = document || {};
  const profile = source.profile || {};

  return {
    version: 1,
    profile: {
      language: profile.language || PROFILE_DEFAULTS.language,
      tone: profile.tone || PROFILE_DEFAULTS.tone,
      formality: profile.formality || PROFILE_DEFAULTS.formality,
      response_length:
        profile.response_length || PROFILE_DEFAULTS.response_length,
    },
    sections: Array.isArray(source.sections)
      ? source.sections.map(normalizeSection)
      : [],
  };
};

export const instructionDocumentForAgent = agent => {
  const savedDocument = agent?.config?.instructions;
  if (savedDocument) return normalizeInstructionDocument(savedDocument);

  return {
    version: 1,
    profile: { ...PROFILE_DEFAULTS },
    sections: [
      {
        key: 'current_instructions',
        title: '',
        content: agent?.prompt || '',
        critical: false,
        custom: false,
      },
    ],
  };
};

export const hasInstructionContent = document =>
  normalizeInstructionDocument(document).sections.some(section =>
    section.content.replace(/<[^>]*>/g, '').trim()
  );

export const instructionContentLength = document =>
  normalizeInstructionDocument(document).sections.reduce(
    (total, section) => total + section.title.length + section.content.length,
    0
  );
