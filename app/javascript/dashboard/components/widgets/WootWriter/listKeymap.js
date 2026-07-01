import { outdentList } from '@chatwoot/prosemirror-schema/src/rules/lists';

export const isEmptyListItemStart = state => {
  const { selection, schema } = state;
  const { list_item: listItem, paragraph } = schema.nodes;

  if (!selection.empty || !listItem || !paragraph) {
    return false;
  }

  const { $from } = selection;

  return (
    $from.parentOffset === 0 &&
    $from.parent.type === paragraph &&
    $from.parent.content.size === 0 &&
    $from.depth > 1 &&
    $from.node($from.depth - 1).type === listItem
  );
};

export const exitEmptyListItem = (state, dispatch) => {
  const { list_item: listItem } = state.schema.nodes;

  if (!isEmptyListItemStart(state) || !listItem) {
    return false;
  }

  return outdentList()(state, dispatch);
};
