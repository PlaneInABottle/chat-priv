import {
  EditorState,
  messageSchema,
  MessageMarkdownSerializer,
  MessageMarkdownTransformer,
  Selection,
} from '@chatwoot/prosemirror-schema';
import { exitEmptyListItem } from '../listKeymap';

const stateFromMarkdown = markdown =>
  EditorState.create({
    schema: messageSchema,
    doc: new MessageMarkdownTransformer(messageSchema).parse(markdown),
  });

const selectionAtEmptyParagraph = state => {
  let paragraphPosition;

  state.doc.descendants((node, position) => {
    if (node.type.name === 'paragraph' && node.content.size === 0) {
      paragraphPosition = position;
    }
  });

  return Selection.near(state.doc.resolve(paragraphPosition + 1));
};

const applySelection = (state, selection) =>
  state.apply(state.tr.setSelection(selection));

const runCommand = (state, command) => {
  let nextState = state;
  const handled = command(state, transaction => {
    nextState = state.apply(transaction);
  });

  return { handled, state: nextState };
};

const serializeAfterTyping = (state, text) =>
  MessageMarkdownSerializer.serialize(
    state.apply(state.tr.insertText(text)).doc
  );

const stateAtEmptyParagraph = markdown => {
  const state = stateFromMarkdown(markdown);
  return applySelection(state, selectionAtEmptyParagraph(state));
};

describe('WootWriter list keymap', () => {
  it('exits an empty bullet list item before typing plain paragraph text', () => {
    const state = stateAtEmptyParagraph('- first\n- ');

    const result = runCommand(state, exitEmptyListItem);

    expect(result.handled).toBe(true);
    expect(serializeAfterTyping(result.state, 'plain text')).toBe(
      '* first\n\nplain text'
    );
  });

  it('exits an empty numbered list item before typing plain paragraph text', () => {
    const state = stateAtEmptyParagraph('1. first\n2. ');

    const result = runCommand(state, exitEmptyListItem);

    expect(result.handled).toBe(true);
    expect(serializeAfterTyping(result.state, 'plain text')).toBe(
      '1. first\n\nplain text'
    );
  });

  it('does not handle Backspace in a non-empty list item', () => {
    const state = stateFromMarkdown('- first\n- second');

    const result = runCommand(state, exitEmptyListItem);

    expect(result.handled).toBe(false);
    expect(MessageMarkdownSerializer.serialize(result.state.doc)).toBe(
      '* first\n\n* second'
    );
  });

  it('keeps typed text out of the previous list item after Backspace', () => {
    const state = stateAtEmptyParagraph('- first\n- ');

    const lifted = runCommand(state, exitEmptyListItem);

    expect(serializeAfterTyping(lifted.state, 'plain text')).toBe(
      '* first\n\nplain text'
    );
  });
});
