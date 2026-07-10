import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { defineComponent, nextTick } from 'vue';
import AiAgentDetail from '../AiAgentDetail.vue';

vi.mock(
  'dashboard/components-next/combobox/TagMultiSelectComboBox.vue',
  () => ({
    default: {
      name: 'TagMultiSelectComboBox',
      template: '<div data-testid="tag-multi-select" />',
      props: [
        'modelValue',
        'options',
        'placeholder',
        'searchPlaceholder',
        'emptyState',
      ],
    },
  })
);

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
  config: {},
  tools_config: {
    enabled: [],
    human_handoff: {
      allowed_labels: [],
    },
    ikas_lookup_order: { enabled: false },
    ikas_catalog_search: {},
  },
  available_tools: [
    { key: 'human_handoff' },
    { key: 'ikas_lookup_order' },
    { key: 'ikas_catalog_search' },
  ],
  ikas_integration: {
    feature_enabled: false,
    state: 'not_connected',
    can_connect: true,
    catalog_sync: {
      status: 'not_synced',
    },
  },
  ...overrides,
});

const createVuexStore = ({
  aiAgentRecord,
  aiAgentRecords,
  updateResult,
  labels = [],
  usage = {
    limit: 10,
    used: 2,
    remaining: 8,
    unlimited: false,
    status: 'ok',
    reset_at: '2026-07-01T00:00:00Z',
    reuse_window_hours: 24,
    metrics: {},
  },
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
    getUsage: vi.fn().mockResolvedValue(usage),
  };

  const store = createStore({
    state: {
      aiAgentRecord: recordsById[1],
      inboxes: [],
      labels,
      usage,
    },
    getters: {
      'aiAgent/getAiAgent': state => state.aiAgentRecord,
      'aiAgent/getUsage': state => state.usage,
      'aiAgent/getUIFlags': () => ({ isFetching: false }),
      'inboxes/getInboxes': state => state.inboxes,
      'labels/getLabels': state => state.labels,
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
      'aiAgent/getUsage': actionMocks.getUsage,
      'labels/get': vi.fn().mockResolvedValue([]),
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
        AiAgentPromptEditor: {
          template: '<textarea>{{ message }}</textarea>',
          props: ['modelValue', 'message', 'messageType', 'maxLength'],
        },
        TabBar: {
          template:
            '<div><button v-for="tab in tabs" :key="tab.value" @click="$emit(\'tabChanged\', tab)">{{ tab.label }}</button></div>',
          props: ['tabs', 'initialActiveTab'],
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

    const inboxCheckboxes = wrapper
      .findAll('input[type="checkbox"]')
      .filter(checkbox => checkbox.attributes('disabled') !== undefined);
    expect(inboxCheckboxes.length).toBeGreaterThan(0);
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

  it('toggles inbox selection once when the row is clicked', async () => {
    const { wrapper } = mountComponent({
      aiAgentRecord: buildAiAgent({
        agent_bot: { inbox_ids: [] },
        available_inboxes: [
          {
            id: 2,
            name: 'Support Inbox',
            channel_type: 'Channel::WebWidget',
            conflicting: false,
          },
        ],
      }),
    });

    await flushPromises();

    const inboxRow = wrapper.find('label[for="inbox-2"]');
    await inboxRow.trigger('click');

    expect(wrapper.vm.formState.inbox_ids).toEqual([2]);

    await inboxRow.trigger('click');

    expect(wrapper.vm.formState.inbox_ids).toEqual([]);
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
    expect(wrapper.vm.promptMessageType).toBe('error');
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

  it('loads labels and exposes existing-label options for human handoff settings', async () => {
    const labels = [
      { id: 1, title: 'billing' },
      { id: 2, title: 'vip' },
    ];
    const { wrapper, actionMocks } = mountComponent({
      labels,
    });

    await flushPromises();

    expect(actionMocks.show).toHaveBeenCalled();
    expect(wrapper.vm.handoffLabelOptions).toEqual([
      { value: 'billing', label: 'billing' },
      { value: 'vip', label: 'vip' },
    ]);
    expect(wrapper.find('[data-testid="tag-multi-select"]').exists()).toBe(
      true
    );
  });

  it('always enables human handoff without rendering a toggle for it', async () => {
    const { wrapper, actionMocks } = mountComponent();

    await flushPromises();

    expect(wrapper.vm.formState.tools.enabled).toContain('human_handoff');
    expect(
      wrapper.find('[data-testid="tool-toggle-human_handoff"]').exists()
    ).toBe(false);

    wrapper.vm.toggleTool('human_handoff');

    expect(wrapper.vm.formState.tools.enabled).toContain('human_handoff');

    await wrapper.vm.handleSave();
    const [, payload] = actionMocks.update.mock.calls.at(-1);
    expect(payload.data.config.tools.enabled).toContain('human_handoff');
  });

  it('hydrates and saves tools subtree config', async () => {
    const { wrapper, actionMocks } = mountComponent({
      aiAgentRecord: buildAiAgent({
        tools_config: {
          enabled: ['human_handoff'],
          human_handoff: {
            allowed_labels: ['vip'],
          },
          ikas_lookup_order: { enabled: false },
          ikas_catalog_search: {},
        },
      }),
    });

    await flushPromises();

    expect(wrapper.vm.formState.tools.enabled).toEqual(['human_handoff']);
    expect(wrapper.vm.formState.tools.human_handoff.allowed_labels).toEqual([
      'vip',
    ]);

    wrapper.vm.updateHandoffLabels(['vip', 'billing']);
    await wrapper.vm.handleSave();

    expect(actionMocks.update).toHaveBeenCalledWith(expect.anything(), {
      id: 1,
      data: expect.objectContaining({
        config: expect.objectContaining({
          tools: expect.objectContaining({
            enabled: ['human_handoff'],
            human_handoff: expect.objectContaining({
              allowed_labels: ['vip', 'billing'],
            }),
          }),
        }),
      }),
    });
  });

  it('saves human handoff config without routing fields', async () => {
    const { wrapper, actionMocks } = mountComponent({
      aiAgentRecord: buildAiAgent({
        tools_config: {
          enabled: ['human_handoff'],
          human_handoff: {
            allowed_labels: ['vip', 'billing'],
          },
          ikas_lookup_order: { enabled: false },
          ikas_catalog_search: {},
        },
      }),
    });

    await flushPromises();
    await wrapper.vm.handleSave();

    const [, payload] = actionMocks.update.mock.calls.at(-1);
    expect(payload.data.config.tools.human_handoff).toEqual({
      allowed_labels: ['vip', 'billing'],
    });
    expect(payload.data.config.tools.human_handoff.team_id).toBeUndefined();
    expect(payload.data.config.tools.human_handoff.assignee_id).toBeUndefined();
  });
});
