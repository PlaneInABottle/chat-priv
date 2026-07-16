import MessageAPI from '../../api/message';

const state = {
  uiFlags: {
    isUpdating: false,
  },
};

export const getters = {
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  select: async (
    { commit, getters: { getUIFlags: uiFlags } },
    { messageId, selectedOption }
  ) => {
    if (uiFlags.isUpdating) return;

    commit('toggleUpdateStatus', true);
    try {
      const response = await MessageAPI.select({
        messageId,
        selectedValue: selectedOption.value,
      });
      commit(
        'conversation/updateMessage',
        {
          id: messageId,
          content_attributes: { submitted_values: [selectedOption] },
        },
        { root: true }
      );
      commit('conversation/pushMessageToConversation', response.data, {
        root: true,
      });
    } catch (error) {
      // Keep the options active so the visitor can retry.
    }
    commit('toggleUpdateStatus', false);
  },
  update: async (
    { commit, dispatch, getters: { getUIFlags: uiFlags } },
    { email, messageId, submittedValues }
  ) => {
    if (uiFlags.isUpdating) {
      return;
    }
    commit('toggleUpdateStatus', true);
    try {
      await MessageAPI.update({
        email,
        messageId,
        values: submittedValues,
      });
      commit(
        'conversation/updateMessage',
        {
          id: messageId,
          content_attributes: {
            submitted_email: email,
            submitted_values: email ? null : submittedValues,
          },
        },
        { root: true }
      );
      dispatch('contacts/get', {}, { root: true });
    } catch (error) {
      // Ignore error
    }
    commit('toggleUpdateStatus', false);
  },
};

export const mutations = {
  toggleUpdateStatus($state, status) {
    $state.uiFlags.isUpdating = status;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
