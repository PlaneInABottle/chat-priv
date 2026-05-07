import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { defineComponent, nextTick } from 'vue';
import AiAgentDetail from '../AiAgentDetail.vue';

vi.mock('vue-router', async importOriginal => {
  const actual = await importOriginal();
  const { reactive } = await import('vue');
  const route = reactive({ params: { id: '1' } });
  const push = vi.fn();

  return {
    ...actual,
    useRoute: () => route,
    useRouter: () => ({ push }),
    setRouteId(id) {
      route.params.id = id;
    },
    resetRoute() {
      route.params.id = '1';
      push.mockReset();
    },
  };
});

import { setRouteId, resetRoute } from 'vue-router';

const buildAiAgent = overrides => ({
  id: 1,
  name: 'Helper',
  enabled: true,
  prompt: 'Persisted prompt',
  agent_bot: { inbox_ids: [2] },
  available_inboxes: [],
  ...overrides,
});

const createVuexStore = ({
  aiAgentRecord,
  aiAgentRecords,
  updateResult,
} = {}) => {
  const recordsById = aiAgentRecords || {
    1: aiAgentRecord || buildAiAgent(),
  };

  const actionMocks = {
    show: vi.fn(async ({ commit }, id) => {
      const record = recordsById[id];
      commit('SET_AI_AGENT_RECORD', record);
      return record;
    }),
    update: vi.fn(async ({ commit }, payload) => {
      if (updateResult) {
        if (updateResult.id) {
          commit('SET_AI_AGENT_RECORD', updateResult);
        }
        return updateResult;
      }

      return payload;
    }),
    reset: vi.fn(),
    get: vi.fn().mockResolvedValue([]),
  };

  const store = createStore({
    state: {
      aiAgentRecord: recordsById[1],
      inboxes: [],
    },
    getters: {
      'aiAgent/getAiAgent': state => state.aiAgentRecord,
      'aiAgent/getUIFlags': () => ({ isFetching: false }),
      'inboxes/getInboxes': state => state.inboxes,
      'aiAgentTestConversations/getTestConversations': () => [],
      'aiAgentTestConversations/getActiveTestConversation': () => null,
      'aiAgentTestConversations/getUIFlags': () => ({}),
    },
    mutations: {
      SET_AI_AGENT_RECORD(state, record) {
        state.aiAgentRecord = record;
      },
    },
    actions: {
      'aiAgent/show': actionMocks.show,
      'aiAgent/update': actionMocks.update,
      'aiAgentTestConversations/reset': actionMocks.reset,
      'aiAgentTestConversations/get': actionMocks.get,
    },
  });

  return { store, actionMocks };
};

const mountComponent = options => {
  const { store, actionMocks } = createVuexStore(options);
  const TestConversationLayoutStub = defineComponent({
    name: 'TestConversationLayout',
    template: '<div class="test-conversation-layout" />',
  });
  const wrapper = mount(AiAgentDetail, {
    global: {
      plugins: [store],
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
        },
        BaseSettingsHeader: { template: '<div />' },
        Button: {
          template: '<button :disabled="disabled"><slot /></button>',
          props: ['label', 'disabled', 'isLoading'],
        },
        Switch: {
          template: '<input type="checkbox" :checked="modelValue" />',
          props: ['modelValue'],
        },
        TextArea: {
          template: '<textarea>{{ message }}</textarea>',
          props: ['message', 'messageType'],
        },
        Avatar: { template: '<div />' },
        Icon: { template: '<i />' },
        TestConversationLayout: TestConversationLayoutStub,
        WootInput: { template: '<input />' },
      },
      mocks: {
        $t: key => key,
      },
    },
  });

  return { wrapper, store, actionMocks };
};

describe('AiAgentDetail.vue', () => {
  beforeEach(() => {
    resetRoute();
  });

  it('renders conflicting inboxes as disabled with owner label', async () => {
    const { wrapper } = mountComponent({
      aiAgentRecord: buildAiAgent({
        agent_bot: { inbox_ids: [1] },
        available_inboxes: [
          {
            id: 1,
            name: 'Current Inbox',
            channel_type: 'Channel::WebWidget',
            conflicting: false,
            owner_name: 'Helper',
          },
          {
            id: 2,
            name: 'Busy Inbox',
            channel_type: 'Channel::Api',
            conflicting: true,
            owner_name: 'Other Agent',
          },
        ],
      }),
    });

    await nextTick();

    const inboxCheckboxes = wrapper.findAll('input[type="checkbox"]').slice(1);
    expect(inboxCheckboxes).toHaveLength(2);
    expect(inboxCheckboxes[1].attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain('Assigned to Other Agent');
  });

  it('shows inbox-specific save error message for validation failures', async () => {
    const { wrapper } = mountComponent({
      aiAgentRecord: buildAiAgent({
        agent_bot: { inbox_ids: [] },
        available_inboxes: [],
      }),
      updateResult: { error: 'already assigned to another agent bot' },
    });

    await nextTick();
    await wrapper.vm.handleSave();
    await nextTick();

    expect(wrapper.text()).toContain('already assigned to another agent bot');
  });

  it('keeps simulator disabled while form is dirty even if local form looks valid', async () => {
    const { wrapper } = mountComponent({
      aiAgentRecord: buildAiAgent({
        enabled: false,
        prompt: '',
        agent_bot: { inbox_ids: [] },
        available_inboxes: [],
      }),
    });

    await nextTick();
    wrapper.vm.formState.enabled = true;
    wrapper.vm.formState.prompt = 'Unsaved prompt';
    await nextTick();

    expect(wrapper.vm.isSimulatorDisabled).toBe(true);
    expect(wrapper.text()).toContain(
      'Save your changes before testing this AI agent.'
    );
  });

  it('shows prompt guidance and keeps save actionable when enabled agent has no prompt', async () => {
    const { wrapper } = mountComponent({
      aiAgentRecord: buildAiAgent({
        name: 'Browser Verify Bot',
        enabled: true,
        prompt: '',
        agent_bot: { inbox_ids: [2] },
        available_inboxes: [],
      }),
    });

    await flushPromises();

    expect(wrapper.vm.isFormDirty).toBe(false);
    expect(wrapper.vm.isSimulatorDisabled).toBe(true);
    expect(wrapper.vm.simulatorDisabledMessageKey).toBe(
      'AI_AGENT.TEST_CONVERSATIONS.ADD_PROMPT_BEFORE_TESTING'
    );
    expect(wrapper.vm.promptMessageKey).toBe(
      'AI_AGENT.PROMPT.REQUIRED_FOR_TESTING'
    );
    expect(wrapper.vm.promptMessageType).toBe('warning');
    expect(wrapper.text()).toContain(
      'Add a system prompt and save your changes before testing this AI agent.'
    );
    expect(wrapper.text()).toContain(
      'Add a system prompt, then save your changes before testing this AI agent.'
    );

    const buttons = wrapper.findAll('button');
    expect(buttons.at(-1).attributes('disabled')).toBeUndefined();
  });

  it('preserves owner labels after save response includes available_inboxes', async () => {
    const updatedRecord = buildAiAgent({
      name: 'Helper Updated',
      available_inboxes: [
        {
          id: 2,
          name: 'Busy Inbox',
          channel_type: 'Channel::Api',
          conflicting: true,
          owner_name: 'Other Agent',
        },
      ],
    });

    const { wrapper, actionMocks } = mountComponent({
      aiAgentRecord: buildAiAgent({
        available_inboxes: [
          {
            id: 2,
            name: 'Busy Inbox',
            channel_type: 'Channel::Api',
            conflicting: true,
            owner_name: 'Other Agent',
          },
        ],
      }),
      updateResult: updatedRecord,
    });

    await nextTick();
    wrapper.vm.formState.name = 'Helper Updated';
    await nextTick();

    await wrapper.vm.handleSave();
    await nextTick();

    expect(actionMocks.update).toHaveBeenCalled();
    expect(wrapper.text()).toContain('Assigned to Other Agent');
  });

  it('reloads agent detail and resets conversations on route param changes', async () => {
    const { wrapper, actionMocks } = mountComponent({
      aiAgentRecords: {
        1: buildAiAgent({ id: 1, name: 'Agent One' }),
        2: buildAiAgent({
          id: 2,
          name: 'Agent Two',
          agent_bot: { inbox_ids: [4] },
        }),
      },
    });

    await flushPromises();
    expect(actionMocks.show).toHaveBeenCalledWith(expect.anything(), 1);
    expect(actionMocks.get).toHaveBeenCalledWith(expect.anything(), {
      aiAgentId: 1,
    });

    actionMocks.reset.mockClear();
    actionMocks.get.mockClear();
    actionMocks.show.mockClear();

    setRouteId('2');
    await nextTick();
    await flushPromises();

    expect(actionMocks.show).toHaveBeenCalledWith(expect.anything(), 2);
    expect(actionMocks.reset).toHaveBeenCalledTimes(1);
    expect(actionMocks.get).toHaveBeenCalledWith(expect.anything(), {
      aiAgentId: 2,
    });
    expect(wrapper.vm.formState.name).toBe('Agent Two');
    expect(wrapper.find('.test-conversation-layout').exists()).toBe(true);
  });
});
