import AiAgentAPI from '../../api/aiAgent';
import { throwErrorMessage } from '../utils/api';

export const state = {
  aiAgent: null,
  uiFlags: {
    isFetching: false,
    isUpdating: false,
  },
};

export const getters = {
  getAiAgent($state) {
    return $state.aiAgent;
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit('SET_AI_AGENT_UI_FLAG', { isFetching: true });
    try {
      const response = await AiAgentAPI.get();
      commit('SET_AI_AGENT', response.data);
    } catch (error) {
      // Ignore error - 404 means no ai agent configured yet
    } finally {
      commit('SET_AI_AGENT_UI_FLAG', { isFetching: false });
    }
  },

  update: async ({ commit }, data) => {
    commit('SET_AI_AGENT_UI_FLAG', { isUpdating: true });
    try {
      const response = await AiAgentAPI.update(data);
      commit('SET_AI_AGENT', response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      return null;
    } finally {
      commit('SET_AI_AGENT_UI_FLAG', { isUpdating: false });
    }
  },
};

export const mutations = {
  SET_AI_AGENT($state, data) {
    $state.aiAgent = data;
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
