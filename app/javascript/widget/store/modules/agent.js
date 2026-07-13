import { getAvailableAgents } from 'widget/api/agent';
import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import { getFromCache, setCache } from 'shared/helpers/cache';

const state = {
  records: [],
  uiFlags: {
    isError: false,
    hasFetched: false,
  },
};

export const getters = {
  getHasFetched: $state => $state.uiFlags.hasFetched,
  availableAgents: $state =>
    $state.records.filter(agent => agent.availability_status === 'online'),
};

const CACHE_KEY_PREFIX = 'kozmopath_available_agents_';

const clearLegacyAgentCache = websiteToken => {
  const cacheSuffix = `_available_agents_${websiteToken}`;
  const currentCacheKey = `${CACHE_KEY_PREFIX}${websiteToken}`;

  Object.keys(localStorage).forEach(key => {
    const isAgentCacheKey =
      key.endsWith(cacheSuffix) || key.endsWith(`${cacheSuffix}:ts`);
    if (isAgentCacheKey && !key.startsWith(currentCacheKey)) {
      localStorage.removeItem(key);
    }
  });
};

export const actions = {
  fetchAvailableAgents: async ({ commit }, websiteToken) => {
    try {
      clearLegacyAgentCache(websiteToken);
      const cachedData = getFromCache(`${CACHE_KEY_PREFIX}${websiteToken}`);
      if (cachedData) {
        commit('setAgents', cachedData);
        commit('setError', false);
        commit('setHasFetched', true);
        return;
      }

      const { data } = await getAvailableAgents(websiteToken);
      const { payload = [] } = data;
      setCache(`${CACHE_KEY_PREFIX}${websiteToken}`, payload);
      commit('setAgents', payload);
      commit('setError', false);
      commit('setHasFetched', true);
    } catch (error) {
      commit('setError', true);
      commit('setHasFetched', true);
    }
  },
  updatePresence: async ({ commit }, data) => {
    commit('updatePresence', data);
  },
};

export const mutations = {
  setAgents($state, data) {
    $state.records = data;
  },
  updatePresence: MutationHelpers.updatePresence,
  setError($state, value) {
    $state.uiFlags.isError = value;
  },
  setHasFetched($state, value) {
    $state.uiFlags.hasFetched = value;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
