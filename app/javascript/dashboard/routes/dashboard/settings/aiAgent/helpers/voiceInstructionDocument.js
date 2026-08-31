import {
  INSTRUCTION_SECTION_KEYS,
  PROFILE_DEFAULTS,
  PROFILE_OPTIONS,
  compileInstructionDocument,
} from './instructionDocument';

export const VOICE_INSTRUCTION_VERSION = 4;
export const VOICE_SECTION_KEYS = ['business_context', 'tasks', 'rules'];
const DOCUMENT_KEYS = ['version', 'locale', 'profile', 'sections'];
const PROFILE_KEYS = Object.keys(PROFILE_DEFAULTS);
const SUPPORTED_LOCALES = ['en', 'tr'];

const assertObject = (value, name) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError(`${name} must be an object`);
  }
};

const rejectUnknownKeys = (value, keys, name) => {
  const unknown = Object.keys(value).filter(key => !keys.includes(key));
  if (unknown.length) throw new TypeError(`Unknown ${name} key: ${unknown[0]}`);
};

export const normalizeVoiceInstructionDocument = document => {
  assertObject(document, 'Voice instruction document');
  rejectUnknownKeys(document, DOCUMENT_KEYS, 'document');
  if (document.version !== VOICE_INSTRUCTION_VERSION) {
    throw new TypeError('Voice instruction version must be 4');
  }
  if (!SUPPORTED_LOCALES.includes(document.locale)) {
    throw new TypeError('Voice instruction locale is invalid');
  }
  assertObject(document.profile, 'Voice instruction profile');
  assertObject(document.sections, 'Voice instruction sections');
  rejectUnknownKeys(document.profile, PROFILE_KEYS, 'profile');
  rejectUnknownKeys(document.sections, VOICE_SECTION_KEYS, 'section');

  const profile = Object.fromEntries(
    PROFILE_KEYS.map(key => {
      const value = document.profile[key];
      if (!PROFILE_OPTIONS[key].includes(value)) {
        throw new TypeError(`Voice instruction profile ${key} is invalid`);
      }
      return [key, value];
    })
  );
  const sections = Object.fromEntries(
    VOICE_SECTION_KEYS.map(key => {
      const value = document.sections[key];
      if (typeof value !== 'string') {
        throw new TypeError(
          `Voice instruction section ${key} must be a string`
        );
      }
      return [key, value];
    })
  );

  return {
    version: VOICE_INSTRUCTION_VERSION,
    locale: document.locale,
    profile,
    sections,
  };
};

export const voiceInstructionDocumentFromLegacy = (prompt, locale = 'en') => {
  if (typeof prompt !== 'string' || !SUPPORTED_LOCALES.includes(locale)) {
    throw new TypeError('Legacy Voice instruction input is invalid');
  }
  return normalizeVoiceInstructionDocument({
    version: VOICE_INSTRUCTION_VERSION,
    locale,
    profile: { ...PROFILE_DEFAULTS },
    sections: { business_context: '', tasks: '', rules: prompt },
  });
};

export const compileVoiceInstructionDocument = document => {
  const normalized = normalizeVoiceInstructionDocument(document);
  const sections = Object.fromEntries(
    INSTRUCTION_SECTION_KEYS.map(key => [key, normalized.sections[key] || ''])
  );
  return compileInstructionDocument({ ...normalized, sections });
};

export const voiceInstructionContentLength = document =>
  Array.from(compileVoiceInstructionDocument(document)).length;
