import { flushPromises, mount } from '@vue/test-utils';

import VoiceAiSettings from '../VoiceAiSettings.vue';

const mocks = vi.hoisted(() => ({
  locale: 'en',
  createAgent: vi.fn(),
  updateAgent: vi.fn(),
  getAgents: vi.fn(),
  getSettings: vi.fn(),
  getUsage: vi.fn(),
  getTelephonyReadiness: vi.fn(),
  endCall: vi.fn(),
  createTestCall: vi.fn(),
  dispatch: vi.fn(),
  alert: vi.fn(),
  creditsRefresh: vi.fn(),
  disconnectRoom: vi.fn(),
  joinRoom: vi.fn(),
  routerReplace: vi.fn(),
  routeLeaveGuard: null,
}));

vi.mock('dashboard/api/voice', () => ({
  default: {
    createAgent: mocks.createAgent,
    updateAgent: mocks.updateAgent,
    getAgents: mocks.getAgents,
    getSettings: mocks.getSettings,
    getUsage: mocks.getUsage,
    getTelephonyReadiness: mocks.getTelephonyReadiness,
    endCall: mocks.endCall,
    createTestCall: mocks.createTestCall,
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
  useMapGetter: () => ({ value: [] }),
}));
vi.mock('dashboard/composables/useVoiceSession', () => ({
  useVoiceSession: () => ({
    remoteAudioRef: { value: null },
    sessionStatus: { value: 'disconnected' },
    sessionError: { value: '' },
    activeParticipantType: { value: '' },
    isJoining: { value: false },
    isMuted: { value: false },
    isConnected: { value: false },
    joinRoom: mocks.joinRoom,
    disconnectRoom: mocks.disconnectRoom,
    toggleMute: vi.fn(),
  }),
}));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  onBeforeRouteLeave: callback => {
    mocks.routeLeaveGuard = callback;
  },
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
  useRouter: () => ({ push: vi.fn(), replace: mocks.routerReplace }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) =>
      `${mocks.locale}:${key}${values.count === undefined ? '' : `:${values.count}`}`,
  }),
}));

const instructions = {
  version: 4,
  locale: 'en',
  profile: {
    language: 'en',
    tone: 'professional',
    formality: 'formal',
    response_length: 'short',
  },
  sections: {
    business_context: 'Retail support',
    tasks: 'Answer order questions.',
    rules: 'Never invent prices.',
  },
};

const savedAgent = (overrides = {}) => ({
  id: 9,
  name: 'Saved assistant',
  greeting: 'Hello',
  prompt: 'Saved legacy instructions',
  instructions,
  knowledge_source_ids: [],
  tools_config: {},
  inbox_settings: [],
  ...overrides,
});

const StructuredEditorStub = {
  name: 'StructuredInstructionEditor',
  props: [
    'modelValue',
    'descriptors',
    'compiledInstructions',
    'contentLength',
    'maxLength',
    'countLabel',
    'disabled',
  ],
  emits: ['update:modelValue'],
  template: '<div data-testid="voice-instruction-editor" />',
};

const ImprovementCreditsSummaryStub = {
  template: '<div />',
  methods: {
    refresh() {
      return mocks.creditsRefresh();
    },
  },
};

const mountComponent = () =>
  mount(VoiceAiSettings, {
    global: {
      stubs: {
        SettingsLayout: { template: '<main><slot name="body" /></main>' },
        BaseSettingsHeader: true,
        ResponsiveTabNavigation: true,
        Button: true,
        Input: true,
        Switch: true,
        StructuredInstructionEditor: StructuredEditorStub,
        KnowledgeSourceSelector: true,
        ImprovementCreditsSummary: ImprovementCreditsSummaryStub,
        AssistantReleaseHistoryDialog: true,
        VoicePublishDialog: true,
        VoiceCallActivity: true,
        VoiceToolEventSummary: true,
      },
    },
  });

const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
};

describe('VoiceAiSettings structured instructions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.locale = 'en';
    mocks.dispatch.mockResolvedValue();
    mocks.getAgents.mockResolvedValue({ data: { payload: [] } });
    mocks.getSettings.mockResolvedValue({ data: { payload: [] } });
    mocks.getUsage.mockResolvedValue({
      data: { enabled: true, unlimited: true },
    });
    mocks.getTelephonyReadiness.mockResolvedValue({
      data: { configured: false, numbers: [] },
    });
    mocks.createAgent.mockResolvedValue({ data: savedAgent() });
    mocks.updateAgent.mockResolvedValue({ data: savedAgent() });
    mocks.endCall.mockResolvedValue({
      data: { id: 77, status: 'completed' },
    });
    mocks.creditsRefresh.mockResolvedValue();
    mocks.routeLeaveGuard = null;
    vi.spyOn(window, 'confirm').mockReturnValue(true);
  });

  it('renders exactly the five Voice entries and no legacy helper or prompt textarea', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    const editor = wrapper.getComponent(StructuredEditorStub);

    expect(editor.props('descriptors').map(item => item.key)).toEqual([
      'all',
      'profile',
      'business_context',
      'tasks',
      'rules',
    ]);
    expect(wrapper.find('textarea[rows="16"]').exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'DraftTestPanel' }).exists()).toBe(
      false
    );
    expect(wrapper.text()).not.toContain('AI_ASSISTANT.INSTRUCTIONS.CONFIGURE');
  });

  it('hydrates canonical instructions without marking the saved agent dirty', async () => {
    mocks.getAgents.mockResolvedValue({ data: { payload: [savedAgent()] } });
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.vm.voiceInstructions).toEqual(instructions);
    expect(wrapper.vm.hasUnsavedAgentChanges).toBe(false);
  });

  it('projects a legacy prompt exactly into rules without appearing dirty', async () => {
    const legacy = savedAgent({
      instructions: null,
      prompt: 'Exact <legacy>\nbody',
    });
    mocks.getAgents.mockResolvedValue({ data: { payload: [legacy] } });
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.vm.voiceInstructions.sections).toEqual({
      business_context: '',
      tasks: '',
      rules: 'Exact <legacy>\nbody',
    });
    expect(wrapper.vm.hasUnsavedAgentChanges).toBe(false);
  });

  it('tracks editor changes and sends only canonical top-level instructions', async () => {
    mocks.getAgents.mockResolvedValue({ data: { payload: [savedAgent()] } });
    const wrapper = mountComponent();
    await flushPromises();
    const updated = {
      ...instructions,
      sections: { ...instructions.sections, rules: 'Updated rule.' },
    };

    await wrapper
      .getComponent(StructuredEditorStub)
      .vm.$emit('update:modelValue', updated);
    expect(wrapper.vm.hasUnsavedAgentChanges).toBe(true);
    await wrapper.vm.saveVoiceAgent();

    const payload = mocks.updateAgent.mock.calls[0][1];
    expect(payload.instructions).toEqual(updated);
    expect(payload).not.toHaveProperty('prompt');
    expect(payload).not.toHaveProperty('config');
    expect(payload).not.toHaveProperty('authoring_profile');
  });

  it('shows compiled preview length and en/tr Voice labels through the shared editor contract', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    let editor = wrapper.getComponent(StructuredEditorStub);

    expect(editor.props('contentLength')).toBe(
      editor.props('compiledInstructions').length
    );
    expect(editor.props('maxLength')).toBe(50000);
    expect(editor.props('descriptors')[0].title).toBe(
      'en:VOICE_AI.INSTRUCTIONS.SECTIONS.ALL.TITLE'
    );

    wrapper.unmount();
    mocks.locale = 'tr';
    const turkishWrapper = mountComponent();
    await flushPromises();
    editor = turkishWrapper.getComponent(StructuredEditorStub);
    expect(editor.props('descriptors')[4].title).toBe(
      'tr:VOICE_AI.INSTRUCTIONS.SECTIONS.RULES.TITLE'
    );
  });

  it('ends an active Test call before committing an internal tab change', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.activeTab = 'test';
    wrapper.vm.currentCall = { id: 77, status: 'in_progress' };

    await wrapper.vm.requestTabTransition('calls');

    expect(mocks.endCall).toHaveBeenCalledWith(77, {
      end_reason: 'browser_test_tab_changed',
    });
    expect(wrapper.vm.currentCall.status).toBe('completed');
    expect(wrapper.vm.activeTab).toBe('calls');
    expect(mocks.disconnectRoom).toHaveBeenCalled();
    expect(mocks.alert).toHaveBeenCalledWith(
      'en:VOICE_AI.SESSION.TAB_CHANGE_END_SUCCESS'
    );
  });

  it('coordinates route-query tab changes through the same ending path', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.activeTab = 'test';
    wrapper.vm.currentCall = { id: 77, status: 'in_progress' };

    await wrapper.vm.requestTabTransition('usage', false);

    expect(mocks.endCall).toHaveBeenCalledOnce();
    expect(wrapper.vm.activeTab).toBe('usage');
    expect(mocks.routerReplace).not.toHaveBeenCalled();
  });

  it('disconnects and navigates with a warning when remote ending fails', async () => {
    mocks.endCall.mockRejectedValueOnce(new Error('network'));
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.activeTab = 'test';
    wrapper.vm.currentCall = { id: 77, status: 'in_progress' };

    await wrapper.vm.requestTabTransition('calls');

    expect(wrapper.vm.activeTab).toBe('calls');
    expect(mocks.disconnectRoom).toHaveBeenCalled();
    expect(mocks.alert).toHaveBeenCalledWith(
      'en:VOICE_AI.SESSION.TAB_CHANGE_END_ERROR'
    );
  });

  it.each([null, { id: 77, status: 'completed' }])(
    'changes tabs without an end request for terminal or absent calls',
    async call => {
      const wrapper = mountComponent();
      await flushPromises();
      wrapper.vm.activeTab = 'test';
      wrapper.vm.currentCall = call;

      await wrapper.vm.requestTabTransition('calls');

      expect(mocks.endCall).not.toHaveBeenCalled();
      expect(wrapper.vm.activeTab).toBe('calls');
    }
  );

  it('deduplicates rapid transitions and commits only the latest destination', async () => {
    const ending = deferred();
    mocks.endCall.mockReturnValueOnce(ending.promise);
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.activeTab = 'test';
    wrapper.vm.currentCall = { id: 77, status: 'in_progress' };

    const first = wrapper.vm.requestTabTransition('calls');
    const second = wrapper.vm.requestTabTransition('recordings');
    ending.resolve({ data: { id: 77, status: 'completed' } });
    await Promise.all([first, second]);

    expect(mocks.endCall).toHaveBeenCalledOnce();
    expect(wrapper.vm.activeTab).toBe('recordings');
    expect(mocks.routerReplace).toHaveBeenCalledOnce();
    expect(mocks.routerReplace.mock.calls[0][0].query.section).toBe(
      'recordings'
    );
  });

  it('does not let an old call completion overwrite a newer call', async () => {
    const ending = deferred();
    mocks.endCall.mockReturnValueOnce(ending.promise);
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.activeTab = 'test';
    wrapper.vm.currentCall = { id: 77, status: 'in_progress' };

    const transition = wrapper.vm.requestTabTransition('calls');
    wrapper.vm.currentCall = { id: 88, status: 'in_progress' };
    ending.resolve({ data: { id: 77, status: 'completed' } });
    await transition;

    expect(wrapper.vm.currentCall).toEqual({ id: 88, status: 'in_progress' });
    expect(wrapper.vm.activeTab).toBe('calls');
  });

  it('never restarts a call when returning to Test', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.activeTab = 'calls';
    wrapper.vm.currentCall = { id: 77, status: 'completed' };

    await wrapper.vm.requestTabTransition('test');

    expect(wrapper.vm.activeTab).toBe('test');
    expect(mocks.createTestCall).not.toHaveBeenCalled();
    expect(mocks.joinRoom).not.toHaveBeenCalled();
  });

  it('preserves manual End confirmation and success behavior', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.currentCall = { id: 77, status: 'in_progress' };

    window.confirm.mockReturnValueOnce(false);
    await wrapper.vm.endCall();
    expect(mocks.endCall).not.toHaveBeenCalled();

    window.confirm.mockReturnValueOnce(true);
    await wrapper.vm.endCall();
    expect(mocks.endCall).toHaveBeenCalledWith(77, {
      end_reason: 'browser_test_ended',
    });
    expect(mocks.alert).toHaveBeenCalledWith('en:VOICE_AI.SESSION.END_SUCCESS');
  });

  it('does not update disposed page state after Manual End resolves during route leave', async () => {
    const ending = deferred();
    mocks.endCall.mockReturnValueOnce(ending.promise);
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.currentCall = { id: 77, status: 'in_progress' };
    window.confirm.mockReturnValueOnce(true);
    const usageCalls = mocks.getUsage.mock.calls.length;
    const alerts = mocks.alert.mock.calls.length;

    const manualEnd = wrapper.vm.endCall();
    await flushPromises();
    expect(mocks.routeLeaveGuard()).toBe(true);
    ending.resolve({ data: { id: 77, status: 'completed' } });
    await manualEnd;
    await flushPromises();

    expect(wrapper.vm.currentCall).toEqual({ id: 77, status: 'in_progress' });
    expect(mocks.getUsage).toHaveBeenCalledTimes(usageCalls);
    expect(mocks.alert).toHaveBeenCalledTimes(alerts);
    expect(mocks.disconnectRoom).toHaveBeenCalled();
  });

  it('stops Manual End follow-up when route leave occurs during usage refresh', async () => {
    const usage = deferred();
    const unhandled = vi.fn();
    window.addEventListener('unhandledrejection', unhandled);
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.currentCall = { id: 77, status: 'in_progress' };
    const originalUsage = wrapper.vm.voiceUsage;
    const usageCalls = mocks.getUsage.mock.calls.length;
    const creditCalls = mocks.creditsRefresh.mock.calls.length;
    const alerts = mocks.alert.mock.calls.length;
    const disconnects = mocks.disconnectRoom.mock.calls.length;
    mocks.getUsage.mockReturnValueOnce(usage.promise);

    const manualEnd = wrapper.vm.endCall();
    await flushPromises();
    expect(mocks.getUsage).toHaveBeenCalledTimes(usageCalls + 1);

    expect(mocks.routeLeaveGuard()).toBe(true);
    usage.resolve({ data: { enabled: false, marker: 'disposed-result' } });
    await manualEnd;
    await flushPromises();

    expect(wrapper.vm.voiceUsage).toBe(originalUsage);
    expect(mocks.creditsRefresh).toHaveBeenCalledTimes(creditCalls);
    expect(mocks.alert).toHaveBeenCalledTimes(alerts);
    expect(unhandled).not.toHaveBeenCalled();
    expect(mocks.disconnectRoom.mock.calls.length).toBeGreaterThan(disconnects);
    window.removeEventListener('unhandledrejection', unhandled);
  });

  it('preserves unsaved-agent cancellation before an internal transition', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.savedAgentSnapshot = 'different';
    wrapper.vm.activeTab = 'agents';
    window.confirm.mockReturnValueOnce(false);

    await wrapper.vm.requestTabTransition('calls');

    expect(wrapper.vm.activeTab).toBe('agents');
    expect(mocks.endCall).not.toHaveBeenCalled();
    expect(mocks.routerReplace).not.toHaveBeenCalled();
  });

  it('allows route leave immediately while safely attempting remote cleanup', async () => {
    const ending = deferred();
    mocks.endCall.mockReturnValueOnce(ending.promise);
    const unhandled = vi.fn();
    window.addEventListener('unhandledrejection', unhandled);
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.activeTab = 'test';
    wrapper.vm.currentCall = { id: 77, status: 'in_progress' };

    expect(mocks.routeLeaveGuard()).toBe(true);
    expect(mocks.disconnectRoom).toHaveBeenCalled();
    expect(mocks.endCall).toHaveBeenCalledWith(77, {
      end_reason: 'browser_test_route_left',
    });

    ending.reject(new Error('offline'));
    await flushPromises();
    expect(unhandled).not.toHaveBeenCalled();
    expect(wrapper.vm.currentCall.status).toBe('in_progress');
    window.removeEventListener('unhandledrejection', unhandled);
  });

  it('performs idempotent local cleanup when unmounted', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    const callsBeforeUnmount = mocks.disconnectRoom.mock.calls.length;

    wrapper.unmount();

    expect(mocks.disconnectRoom).toHaveBeenCalledTimes(callsBeforeUnmount + 1);
  });
});
