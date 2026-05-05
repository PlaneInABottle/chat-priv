import AiAgentTestConversationsAPI from '../../api/aiAgentTestConversations';
import { throwErrorMessage } from '../utils/api';

export const state = {
  records: {},
  sortOrder: [],
  activeId: null,
  uiFlags: {
    isFetching: false,
    isFetchingItem: false,
    isCreating: false,
    isDeleting: false,
    isSending: false,
  },
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
  get: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await AiAgentTestConversationsAPI.get();
      commit('SET_CONVERSATIONS', response.data);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  show: async ({ commit }, id) => {
    commit('SET_UI_FLAG', { isFetchingItem: true });
    try {
      const response = await AiAgentTestConversationsAPI.show(id);
      commit('SET_CONVERSATION_ITEM', response.data);
      commit('SET_ACTIVE_ID', response.data.id);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetchingItem: false });
    }
  },

  create: async ({ commit }) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const response = await AiAgentTestConversationsAPI.create();
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

  delete: async ({ commit }, id) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await AiAgentTestConversationsAPI.delete(id);
      commit('REMOVE_CONVERSATION', id);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },

  clearAll: async ({ commit }) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await AiAgentTestConversationsAPI.clearAll();
      commit('CLEAR_ALL_CONVERSATIONS');
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },

  sendMessage: async ({ commit }, { id, content }) => {
    commit('SET_UI_FLAG', { isSending: true });

    // Optimistically add user message so it appears immediately
    const optimisticMessage = {
      id: `temp-${Date.now()}`,
      role: 'user',
      content,
      created_at: new Date().toISOString(),
    };
    commit('ADD_MESSAGE', { id, message: optimisticMessage });

    try {
      const response = await AiAgentTestConversationsAPI.sendMessage(
        id,
        content
      );
      commit('UPDATE_MESSAGES', {
        id,
        messages: response.data.messages,
        title: response.data.title,
      });
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      return null;
    } finally {
      commit('SET_UI_FLAG', { isSending: false });
    }
  },

  setActiveId: async ({ commit }, id) => {
    commit('SET_ACTIVE_ID', id);
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
  UPDATE_MESSAGES($state, { id, messages, title }) {
    if ($state.records[id]) {
      $state.records[id].messages = messages;
      $state.records[id].messages_count = messages.length;
      $state.records[id].last_message_at =
        messages.length > 0 ? messages[messages.length - 1].created_at : null;
      $state.records[id].last_message_preview =
        messages.length > 0
          ? messages[messages.length - 1].content?.substring(0, 60)
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
      $state.records[id].last_message_preview =
        message.content?.substring(0, 60) ?? null;
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
