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
  en: {
    identity: 'Identity and purpose',
    business_context: 'Business context',
    tasks: 'Tasks and conversation flow',
    rules: 'Rules and boundaries',
    handoff: 'Human handoff',
    examples: 'Example conversations',
    additional: 'Additional instructions',
  },
  tr: {
    identity: 'Kimlik ve amaç',
    business_context: 'İşletme bilgileri',
    tasks: 'Görevler ve konuşma akışı',
    rules: 'Kurallar ve sınırlar',
    handoff: 'İnsan desteğine aktarım',
    examples: 'Örnek konuşmalar',
    additional: 'Ek talimatlar',
  },
};

const PROFILE_FIELD_NAMES = {
  en: {
    language: 'Reply language',
    tone: 'Tone',
    formality: 'Formality',
    response_length: 'Response length',
  },
  tr: {
    language: 'Yanıt dili',
    tone: 'Üslup',
    formality: 'Resmiyet',
    response_length: 'Yanıt uzunluğu',
  },
};

const PROFILE_PROMPT_LABELS = {
  en: {
    language: {
      same_as_customer: "Use the customer's language",
      tr: 'Turkish',
      en: 'English',
    },
    tone: {
      natural: 'Natural',
      friendly: 'Friendly',
      professional: 'Professional',
      concise: 'Concise',
    },
    formality: { balanced: 'Balanced', casual: 'Casual', formal: 'Formal' },
    response_length: {
      balanced: 'Balanced',
      short: 'Short',
      detailed: 'Detailed',
    },
  },
  tr: {
    language: {
      same_as_customer: 'Müşterinin dilini kullan',
      tr: 'Türkçe',
      en: 'İngilizce',
    },
    tone: {
      natural: 'Doğal',
      friendly: 'Samimi',
      professional: 'Profesyonel',
      concise: 'Öz',
    },
    formality: { balanced: 'Dengeli', casual: 'Gündelik', formal: 'Resmi' },
    response_length: {
      balanced: 'Dengeli',
      short: 'Kısa',
      detailed: 'Ayrıntılı',
    },
  },
};

const normalizeText = value => String(value || '').trim();

const emptySections = () =>
  Object.fromEntries(INSTRUCTION_SECTION_KEYS.map(key => [key, '']));

const supportedLocale = value => (['tr', 'en'].includes(value) ? value : null);

const instructionLocale = source =>
  supportedLocale(source?.locale) ||
  supportedLocale(source?.profile?.language) ||
  (Number(source?.version) >= 4 ? 'tr' : 'en');

export const createDefaultInstructionDocument = (locale = 'tr') => ({
  version: 4,
  locale: supportedLocale(locale) || 'tr',
  profile: { ...NEW_ASSISTANT_PROFILE_DEFAULTS },
  sections: emptySections(),
});

export const normalizeInstructionDocument = document => {
  const source = document || {};
  const profile = source.profile || {};
  const sections = source.sections || {};

  return {
    version: 4,
    locale: document ? instructionLocale(source) : 'tr',
    profile: {
      language: profile.language || PROFILE_DEFAULTS.language,
      tone:
        profile.tone === 'warm'
          ? 'friendly'
          : profile.tone || PROFILE_DEFAULTS.tone,
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
    version: 4,
    locale: 'en',
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
  const locale = normalized.locale;
  const profileLines = Object.entries(PROFILE_PROMPT_LABELS[locale])
    .map(([key, labels]) => {
      const label = labels[normalized.profile[key]];
      return label ? `- ${PROFILE_FIELD_NAMES[locale][key]}: ${label}` : '';
    })
    .filter(Boolean);
  const profilePrompt = profileLines.length
    ? `## ${locale === 'tr' ? 'Dil ve üslup' : 'Language and tone'}\n${profileLines.join('\n')}`
    : '';
  const sectionPrompts = INSTRUCTION_SECTION_KEYS.map(key => {
    const content = normalizeText(normalized.sections[key]);
    return content
      ? `## ${INSTRUCTION_SECTION_TITLES[locale][key]}\n\n${content}`
      : '';
  }).filter(Boolean);

  return [profilePrompt, ...sectionPrompts].filter(Boolean).join('\n\n');
};

export const instructionContentLength = document =>
  compileInstructionDocument(document).length;
