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
  dispatch: vi.fn(),
}));

vi.mock('dashboard/api/voice', () => ({
  default: {
    createAgent: mocks.createAgent,
    updateAgent: mocks.updateAgent,
    getAgents: mocks.getAgents,
    getSettings: mocks.getSettings,
    getUsage: mocks.getUsage,
    getTelephonyReadiness: mocks.getTelephonyReadiness,
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
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
    joinRoom: vi.fn(),
    disconnectRoom: vi.fn(),
    toggleMute: vi.fn(),
  }),
}));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  onBeforeRouteLeave: vi.fn(),
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));

const translations = {
  en: {
    'VOICE_AI.CREATE.TONES.FRIENDLY': 'Friendly',
    'VOICE_AI.CREATE.DRAFT.ROLE': 'Role: You are {name} for customer calls.',
    'VOICE_AI.CREATE.DRAFT.TONE':
      'Tone: {tone}. Speak naturally and keep answers easy to follow aloud.',
    'VOICE_AI.CREATE.DRAFT.BUSINESS_CONTEXT': 'Business context: {context}',
    'VOICE_AI.CREATE.DRAFT.BOUNDARIES': 'Boundaries: {boundaries}',
    'VOICE_AI.CREATE.DRAFT.HANDOFF': 'Request human support when needed.',
  },
  tr: {
    'VOICE_AI.CREATE.TONES.FRIENDLY': 'Samimi',
    'VOICE_AI.CREATE.DRAFT.ROLE':
      'Rol: Müşteri çağrıları için {name} olarak görev yap.',
    'VOICE_AI.CREATE.DRAFT.TONE':
      'Ton: {tone}. Doğal konuş ve kolay anlaşılmasını sağla.',
    'VOICE_AI.CREATE.DRAFT.BUSINESS_CONTEXT': 'İşletme bağlamı: {context}',
    'VOICE_AI.CREATE.DRAFT.BOUNDARIES': 'Sınırlar: {boundaries}',
    'VOICE_AI.CREATE.DRAFT.HANDOFF': 'Gerektiğinde insan desteği talep et.',
  },
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) => {
      let text = translations[mocks.locale][key] || key;
      Object.entries(values).forEach(([name, value]) => {
        text = text.replace(`{${name}}`, value);
      });
      return text;
    },
  }),
}));

const ButtonStub = {
  props: ['label', 'disabled'],
  emits: ['click'],
  template:
    '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
};

const mountComponent = () =>
  mount(VoiceAiSettings, {
    global: {
      stubs: {
        SettingsLayout: { template: '<main><slot name="body" /></main>' },
        BaseSettingsHeader: true,
        ResponsiveTabNavigation: true,
        Button: ButtonStub,
        Input: true,
        Switch: true,
        KnowledgeSourceSelector: true,
        ImprovementCreditsSummary: true,
        AssistantReleaseHistoryDialog: true,
        VoicePublishDialog: true,
        VoiceCallActivity: true,
        VoiceToolEventSummary: true,
      },
    },
  });

describe('VoiceAiSettings.vue', () => {
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
    mocks.createAgent.mockResolvedValue({ data: { id: 9, name: 'Assistant' } });
    mocks.updateAgent.mockResolvedValue({ data: { id: 9, name: 'Assistant' } });
  });

  it('renders the goal-free builder in tone, context, boundaries, action order', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    const text = wrapper.text();

    expect(text).not.toContain('Primary goal');
    const keys = [
      'VOICE_AI.CREATE.TONE',
      'VOICE_AI.CREATE.BUSINESS_CONTEXT',
      'VOICE_AI.CREATE.BOUNDARIES',
      'VOICE_AI.CREATE.BUILD_INSTRUCTIONS',
    ];
    const positions = keys.map(key => text.indexOf(key));
    positions.forEach(position => expect(position).toBeGreaterThanOrEqual(0));
    expect(positions).toEqual([...positions].sort((a, b) => a - b));
  });

  it('builds localized instructions into the editable prompt', async () => {
    mocks.locale = 'tr';
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.agentForm.name = 'Destek asistanı';
    wrapper.vm.voiceSetupProfile.businessContext = 'Sipariş desteği';
    wrapper.vm.voiceSetupProfile.boundaries = 'İade onayı verme';

    wrapper.vm.buildVoiceInstructions();
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.agentForm.prompt).toContain(
      'Rol: Müşteri çağrıları için Destek asistanı'
    );
    expect(wrapper.vm.agentForm.prompt).toContain('Ton: Samimi');
    expect(wrapper.vm.agentForm.prompt).toContain(
      'İşletme bağlamı: Sipariş desteği'
    );
    expect(wrapper.vm.agentForm.prompt).toContain('Sınırlar: İade onayı verme');
    const prompt = wrapper.get('textarea[rows="10"]');
    await prompt.setValue('Kullanıcı tarafından düzenlendi');
    expect(wrapper.vm.agentForm.prompt).toBe('Kullanıcı tarafından düzenlendi');
  });

  it('never sends goal fields when creating or updating an assistant', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.agentForm.name = 'Assistant';
    await wrapper.vm.$nextTick();
    await wrapper.vm.saveVoiceAgent();

    expect(mocks.createAgent).toHaveBeenCalledOnce();
    expect(mocks.createAgent.mock.calls[0][0]).not.toHaveProperty('goal');
    expect(mocks.createAgent.mock.calls[0][0]).not.toHaveProperty(
      'primary_goal'
    );

    wrapper.vm.editingVoiceAgentId = 9;
    wrapper.vm.savedAgentSnapshot = 'outdated';
    await wrapper.vm.saveVoiceAgent();
    expect(mocks.updateAgent).toHaveBeenCalledOnce();
    expect(mocks.updateAgent.mock.calls[0][1]).not.toHaveProperty('goal');
    expect(mocks.updateAgent.mock.calls[0][1]).not.toHaveProperty(
      'primary_goal'
    );
  });
});
