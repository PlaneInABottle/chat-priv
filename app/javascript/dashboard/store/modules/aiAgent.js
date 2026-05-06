import AiAgentAPI from '../../api/aiAgent';
import { parseAPIErrorResponse, throwErrorMessage } from '../utils/api';

export const state = {
  records: {},
  sortOrder: [],
  activeId: null,
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getAiAgents($state) {
    return $state.sortOrder.map(id => $state.records[id]);
  },
  getAiAgent($state) {
    return $state.records[$state.activeId] || null;
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getActiveAgent($state) {
    return $state.records[$state.activeId] || null;
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit('SET_AI_AGENT_UI_FLAG', { isFetching: true });
    try {
      const response = await AiAgentAPI.get();
      const agents = Array.isArray(response.data) ? response.data : [];
      commit('SET_AI_AGENTS', agents);
      if (agents.length === 1) {
        commit('SET_ACTIVE_AI_AGENT_ID', agents[0].id);
      }
    } catch (error) {
      // Ignore error - 404 means no ai agent configured yet
    } finally {
      commit('SET_AI_AGENT_UI_FLAG', { isFetching: false });
    }
  },

  show: async ({ commit }, id) => {
    commit('SET_AI_AGENT_UI_FLAG', { isFetching: true });
    try {
      const response = await AiAgentAPI.show(id);
      commit('SET_AI_AGENT', response.data);
      commit('SET_ACTIVE_AI_AGENT_ID', response.data.id);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      return null;
    } finally {
      commit('SET_AI_AGENT_UI_FLAG', { isFetching: false });
    }
  },

  create: async ({ commit }, data) => {
    commit('SET_AI_AGENT_UI_FLAG', { isCreating: true });
    try {
      const response = await AiAgentAPI.create(data);
      commit('ADD_AI_AGENT', response.data);
      return response.data;
    } catch (error) {
      return {
        error: parseAPIErrorResponse(error),
      };
    } finally {
      commit('SET_AI_AGENT_UI_FLAG', { isCreating: false });
    }
  },

  update: async ({ commit, state: storeState }, payload) => {
    let id;
    let data;
    if (payload && payload.id !== undefined && payload.data !== undefined) {
      ({ id, data } = payload);
    } else {
      data = payload;
      id = storeState.activeId;
    }
    if (!id) {
      return null;
    }
    commit('SET_AI_AGENT_UI_FLAG', { isUpdating: true });
    try {
      const response = await AiAgentAPI.update(id, data);
      commit('UPDATE_AI_AGENT', response.data);
      return response.data;
    } catch (error) {
      return {
        error: parseAPIErrorResponse(error),
      };
    } finally {
      commit('SET_AI_AGENT_UI_FLAG', { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit('SET_AI_AGENT_UI_FLAG', { isDeleting: true });
    try {
      await AiAgentAPI.delete(id);
      commit('DELETE_AI_AGENT', id);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_AI_AGENT_UI_FLAG', { isDeleting: false });
    }
  },
};

export const mutations = {
  SET_AI_AGENTS($state, data) {
    $state.records = {};
    $state.sortOrder = [];
    data.forEach(item => {
      $state.records[item.id] = item;
      $state.sortOrder.push(item.id);
    });
  },
  SET_AI_AGENT($state, data) {
    $state.records[data.id] = { ...($state.records[data.id] || {}), ...data };
    if (!$state.sortOrder.includes(data.id)) {
      $state.sortOrder.push(data.id);
    }
  },
  SET_ACTIVE_AI_AGENT_ID($state, id) {
    $state.activeId = id;
  },
  ADD_AI_AGENT($state, data) {
    $state.records[data.id] = data;
    $state.sortOrder.push(data.id);
  },
  UPDATE_AI_AGENT($state, data) {
    $state.records[data.id] = { ...($state.records[data.id] || {}), ...data };
    if (!$state.sortOrder.includes(data.id)) {
      $state.sortOrder.push(data.id);
    }
  },
  DELETE_AI_AGENT($state, id) {
    const index = $state.sortOrder.findIndex(i => i === id);
    if (index !== -1) $state.sortOrder.splice(index, 1);
    delete $state.records[id];
    if ($state.activeId === id) {
      $state.activeId = null;
    }
  },
  SET_AI_AGENT_UI_FLAG($state, data) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...data,
    };
  },
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
