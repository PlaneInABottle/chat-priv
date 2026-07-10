import AiAgentTestConversationsAPI from '../../api/aiAgentTestConversations';
import { parseAPIErrorResponse, throwErrorMessage } from '../utils/api';

export const state = {
  records: {},
  sortOrder: [],
  activeId: null,
  uiFlags: {
    isFetching: false,
    isFetchingItem: false,
    isCreating: false,
    isDeleting: false,
    isClearing: false,
    isSending: false,
  },
};

const getMessagePreview = message => {
  if (!message) return null;
  if (message.content) return message.content.substring(0, 60);
  if (message.terminal_action === 'handoff') {
    return (
      message.tool_result?.customer_message || 'Human handoff preview'
    ).substring(0, 60);
  }

  return null;
};

export const getters = {
  getTestConversations($state) {
    return $state.sortOrder.map(id => $state.records[id]);
  },
  getActiveTestConversation($state) {
    return $state.activeId ? $state.records[$state.activeId] : null;
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit, rootState }, payload = {}) => {
    const { aiAgentId } = payload;
    const resolvedAiAgentId = aiAgentId || rootState.aiAgent.activeId;
    if (!resolvedAiAgentId) return;

    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const api = new AiAgentTestConversationsAPI(resolvedAiAgentId);
      const response = await api.get();
      const activeAiAgentId = rootState.aiAgent.activeId;
      if (activeAiAgentId && activeAiAgentId !== resolvedAiAgentId) {
        return;
      }
      commit('SET_CONVERSATIONS', response.data);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  show: async ({ commit, rootState }, payload) => {
    let aiAgentId;
    let id;
    if (typeof payload === 'object') {
      ({ aiAgentId, id } = payload);
    } else {
      id = payload;
    }
    const resolvedAiAgentId = aiAgentId || rootState.aiAgent.activeId;
    if (!resolvedAiAgentId || !id) return;

    commit('SET_UI_FLAG', { isFetchingItem: true });
    try {
      const api = new AiAgentTestConversationsAPI(resolvedAiAgentId);
      const response = await api.show(id);
      commit('SET_CONVERSATION_ITEM', response.data);
      commit('SET_ACTIVE_ID', response.data.id);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetchingItem: false });
    }
  },

  create: async ({ commit, rootState }, payload = {}) => {
    const { aiAgentId, title } = payload;
    const resolvedAiAgentId = aiAgentId || rootState.aiAgent.activeId;
    if (!resolvedAiAgentId) return null;

    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const api = new AiAgentTestConversationsAPI(resolvedAiAgentId);
      const response = await api.create(title ? { title } : {});
      commit('SET_CONVERSATION_ITEM', response.data);
      commit('SET_ACTIVE_ID', response.data.id);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      return null;
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },

  delete: async ({ commit, rootState }, payload) => {
    let aiAgentId;
    let id;
    if (typeof payload === 'object') {
      ({ aiAgentId, id } = payload);
    } else {
      id = payload;
    }
    const resolvedAiAgentId = aiAgentId || rootState.aiAgent.activeId;
    if (!resolvedAiAgentId || !id) return;

    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      const api = new AiAgentTestConversationsAPI(resolvedAiAgentId);
      await api.delete(id);
      commit('REMOVE_CONVERSATION', id);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },

  clearAll: async ({ commit, rootState }, payload = {}) => {
    const { aiAgentId } = payload;
    const resolvedAiAgentId = aiAgentId || rootState.aiAgent.activeId;
    if (!resolvedAiAgentId) return;

    commit('SET_UI_FLAG', { isClearing: true });
    try {
      const api = new AiAgentTestConversationsAPI(resolvedAiAgentId);
      await api.clearAll();
      commit('CLEAR_ALL_CONVERSATIONS');
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isClearing: false });
    }
  },

  sendMessage: async ({ commit, rootState }, payload) => {
    const { aiAgentId, id, message, content, draftInstructions } =
      payload || {};
    const resolvedAiAgentId = aiAgentId || rootState.aiAgent.activeId;
    if (!resolvedAiAgentId || !id) return null;

    const messageContent = content || message;
    if (!messageContent) return null;

    commit('SET_UI_FLAG', { isSending: true });

    // Optimistically add user message so it appears immediately
    const optimisticMessage = {
      id: `temp-${Date.now()}`,
      role: 'user',
      content: messageContent,
      created_at: new Date().toISOString(),
    };
    commit('ADD_MESSAGE', { id, message: optimisticMessage });

    try {
      const api = new AiAgentTestConversationsAPI(resolvedAiAgentId);
      const response = await api.sendMessage(
        id,
        messageContent,
        draftInstructions
      );
      commit('UPDATE_MESSAGES', {
        id,
        messages: response.data.messages,
        title: response.data.title,
      });
      return response.data;
    } catch (error) {
      commit('REMOVE_MESSAGE', { id, messageId: optimisticMessage.id });
      return { error: parseAPIErrorResponse(error) };
    } finally {
      commit('SET_UI_FLAG', { isSending: false });
    }
  },

  setActiveId: async ({ commit }, id) => {
    commit('SET_ACTIVE_ID', id);
  },

  reset: ({ commit }) => {
    commit('RESET_CONVERSATIONS_STATE');
  },
};

export const mutations = {
  SET_UI_FLAG($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },
  SET_CONVERSATIONS($state, data) {
    $state.records = {};
    $state.sortOrder = [];
    data.forEach(item => {
      $state.records[item.id] = item;
      $state.sortOrder.push(item.id);
    });
    if (!$state.sortOrder.includes($state.activeId)) {
      $state.activeId = null;
    }
  },
  SET_CONVERSATION_ITEM($state, data) {
    $state.records[data.id] = { ...($state.records[data.id] || {}), ...data };
    if (!$state.sortOrder.includes(data.id)) {
      $state.sortOrder.push(data.id);
    }
  },
  REMOVE_CONVERSATION($state, id) {
    const index = $state.sortOrder.findIndex(i => i === id);
    if (index !== -1) $state.sortOrder.splice(index, 1);
    delete $state.records[id];
    if ($state.activeId === id) {
      $state.activeId = null;
    }
  },
  CLEAR_ALL_CONVERSATIONS($state) {
    $state.records = {};
    $state.sortOrder = [];
    $state.activeId = null;
  },
  RESET_CONVERSATIONS_STATE($state) {
    $state.records = {};
    $state.sortOrder = [];
    $state.activeId = null;
  },
  UPDATE_MESSAGES($state, { id, messages, title }) {
    if ($state.records[id]) {
      $state.records[id].messages = messages;
      $state.records[id].messages_count = messages.length;
      $state.records[id].last_message_at =
        messages.length > 0 ? messages[messages.length - 1].created_at : null;
      $state.records[id].last_message_preview =
        messages.length > 0
          ? getMessagePreview(messages[messages.length - 1])
          : null;
      if (title) {
        $state.records[id].title = title;
      }
    }
  },
  ADD_MESSAGE($state, { id, message }) {
    if ($state.records[id]) {
      $state.records[id].messages = [...$state.records[id].messages, message];
      $state.records[id].messages_count = $state.records[id].messages.length;
      $state.records[id].last_message_at = message.created_at;
      $state.records[id].last_message_preview = getMessagePreview(message);
    }
  },
  REMOVE_MESSAGE($state, { id, messageId }) {
    if ($state.records[id]) {
      $state.records[id].messages = $state.records[id].messages.filter(
        message => message.id !== messageId
      );
      $state.records[id].messages_count = $state.records[id].messages.length;
      const lastMessage = $state.records[id].messages.at(-1);
      $state.records[id].last_message_at = lastMessage?.created_at ?? null;
      $state.records[id].last_message_preview = getMessagePreview(lastMessage);
    }
  },
  SET_ACTIVE_ID($state, id) {
    $state.activeId = id;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
