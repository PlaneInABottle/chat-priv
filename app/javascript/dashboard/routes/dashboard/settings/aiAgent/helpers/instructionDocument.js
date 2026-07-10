import {
  ArticleMarkdownSerializer,
  fullSchema,
} from '@chatwoot/prosemirror-schema';
import { DOMParser as ProseMirrorDOMParser } from 'prosemirror-model';

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

export const STANDARD_SECTION_HEADINGS = [
  ['identity', 'Identity and purpose'],
  ['business_context', 'Business context'],
  ['tasks', 'Tasks and conversation flow'],
  ['rules', 'Rules and boundaries'],
  ['handoff', 'Human handoff'],
  ['examples', 'Example conversations'],
];

const LEGACY_SECTION_TITLES = {
  current_instructions: 'General instructions',
  ...Object.fromEntries(STANDARD_SECTION_HEADINGS),
};

const normalizeText = value => String(value || '').trim();

const legacyContentToMarkdown = value => {
  const content = normalizeText(value);
  if (!content.match(/<\/?[a-z][^>]*>/i)) return content;

  const container = document.createElement('div');
  container.innerHTML = content;
  const parsedContent =
    ProseMirrorDOMParser.fromSchema(fullSchema).parse(container);
  return ArticleMarkdownSerializer.serialize(parsedContent).trim();
};

export const createInstructionContent = (contentBySection = {}) =>
  STANDARD_SECTION_HEADINGS.map(
    ([key, title]) => `## ${title}\n\n${normalizeText(contentBySection[key])}`
  ).join('\n\n');

const legacySectionsToContent = sections =>
  sections
    .map(section => {
      const title =
        LEGACY_SECTION_TITLES[section?.key] || section?.title || 'Section';
      return `## ${title}\n\n${legacyContentToMarkdown(section?.content)}`;
    })
    .join('\n\n');

export const createDefaultInstructionDocument = () => ({
  version: 2,
  profile: { ...NEW_ASSISTANT_PROFILE_DEFAULTS },
  content: createInstructionContent(),
});

export const normalizeInstructionDocument = document => {
  const source = document || {};
  const profile = source.profile || {};

  return {
    version: 2,
    profile: {
      language: profile.language || PROFILE_DEFAULTS.language,
      tone: profile.tone || PROFILE_DEFAULTS.tone,
      formality: profile.formality || PROFILE_DEFAULTS.formality,
      response_length:
        profile.response_length || PROFILE_DEFAULTS.response_length,
    },
    content:
      source.content ??
      legacySectionsToContent(
        Array.isArray(source.sections) ? source.sections : []
      ),
  };
};

export const instructionDocumentForAgent = agent => {
  const savedDocument = agent?.config?.instructions;
  if (savedDocument) return normalizeInstructionDocument(savedDocument);

  const generalInstructions = `## General instructions\n\n${normalizeText(agent?.prompt)}`;
  return {
    version: 2,
    profile: { ...PROFILE_DEFAULTS },
    content: `${generalInstructions}\n\n${createInstructionContent()}`,
  };
};

export const hasInstructionContent = document => {
  const withoutHeadings = normalizeInstructionDocument(
    document
  ).content.replace(/^#{1,6}\s+.+$/gm, '');
  return Boolean(withoutHeadings.trim());
};

export const instructionContentLength = document =>
  normalizeInstructionDocument(document).content.length;
