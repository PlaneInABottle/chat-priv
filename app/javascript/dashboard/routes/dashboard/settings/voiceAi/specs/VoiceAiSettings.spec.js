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
    'VOICE_AI.CREATE.DRAFT_ADDED': 'Draft added to Instructions.',
    'VOICE_AI.CREATE.REPLACE_CONFIRM': 'Replace edited instructions?',
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
    'VOICE_AI.CREATE.DRAFT_ADDED': 'Taslak Yönergeler alanına eklendi.',
    'VOICE_AI.CREATE.REPLACE_CONFIRM':
      'Düzenlenen yönergeler değiştirilsin mi?',
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
    attachTo: document.body,
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

const savedAgent = (overrides = {}) => ({
  id: 9,
  name: 'Saved assistant',
  greeting: 'Hello',
  prompt: 'Saved instructions',
  knowledge_source_ids: [],
  tools_config: {},
  inbox_settings: [],
  authoring_profile: {
    tone: 'professional',
    business_context: 'Retail support',
    boundaries: 'Do not approve refunds',
  },
  ...overrides,
});

describe('VoiceAiSettings.vue', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
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
    Element.prototype.scrollIntoView = vi.fn();
    vi.spyOn(window, 'confirm').mockReturnValue(true);
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
    const prompt = wrapper.get('textarea[rows="16"]');
    expect(prompt.classes()).toContain('min-h-80');
    expect(prompt.classes()).toContain('resize-y');
  });

  it('hydrates and renders the helper for a saved assistant', async () => {
    mocks.getAgents.mockResolvedValue({ data: { payload: [savedAgent()] } });
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.vm.editingVoiceAgentId).toBe(9);
    expect(wrapper.vm.voiceSetupProfile).toEqual({
      tone: 'professional',
      businessContext: 'Retail support',
      boundaries: 'Do not approve refunds',
    });
    expect(wrapper.get('select').element.value).toBe('professional');
    expect(wrapper.html().indexOf('VOICE_AI.CREATE.TITLE')).toBeLessThan(
      wrapper.html().indexOf('VOICE_AI.AGENTS.PROMPT')
    );
  });

  it('uses safe field-by-field profile defaults for missing and malformed responses', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    wrapper.vm.syncAgentForm(savedAgent({ authoring_profile: undefined }));
    expect(wrapper.vm.voiceSetupProfile).toEqual({
      tone: 'friendly',
      businessContext: '',
      boundaries: '',
    });

    wrapper.vm.syncAgentForm(
      savedAgent({
        authoring_profile: {
          tone: 'invalid',
          business_context: 'Valid context',
          boundaries: 4,
        },
      })
    );
    expect(wrapper.vm.voiceSetupProfile).toEqual({
      tone: 'friendly',
      businessContext: 'Valid context',
      boundaries: '',
    });

    wrapper.vm.syncAgentForm(null);
    expect(wrapper.vm.voiceSetupProfile).toEqual({
      tone: 'friendly',
      businessContext: '',
      boundaries: '',
    });
  });

  it('dirty-tracks helper-only edits without changing instructions', async () => {
    mocks.getAgents.mockResolvedValue({ data: { payload: [savedAgent()] } });
    const wrapper = mountComponent();
    await flushPromises();
    const originalPrompt = wrapper.vm.agentForm.prompt;

    expect(wrapper.vm.hasUnsavedAgentChanges).toBe(false);
    await wrapper.get('textarea[rows="3"]').setValue('Updated context');

    expect(wrapper.vm.hasUnsavedAgentChanges).toBe(true);
    expect(wrapper.vm.canSaveAgent).toBe(true);
    expect(wrapper.vm.agentForm.prompt).toBe(originalPrompt);
  });

  it('disables and bounds all helper controls when Voice access is disabled', async () => {
    mocks.getUsage.mockResolvedValue({ data: { enabled: false } });
    const wrapper = mountComponent();
    await flushPromises();
    const helperTextareas = wrapper.findAll('textarea[rows="3"]');

    expect(wrapper.get('select').attributes('disabled')).toBeDefined();
    expect(helperTextareas).toHaveLength(2);
    helperTextareas.forEach(textarea => {
      expect(textarea.attributes('disabled')).toBeDefined();
      expect(textarea.attributes('maxlength')).toBe('2000');
    });
    expect(
      wrapper
        .findAll('button')
        .find(button => button.text() === 'VOICE_AI.CREATE.BUILD_INSTRUCTIONS')
        .attributes('disabled')
    ).toBeDefined();
  });

  it('builds localized instructions, focuses the prompt, and keeps it editable', async () => {
    mocks.locale = 'tr';
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.agentForm.name = 'Destek asistanı';
    wrapper.vm.voiceSetupProfile.businessContext = 'Sipariş desteği';
    wrapper.vm.voiceSetupProfile.boundaries = 'İade onayı verme';

    await wrapper.vm.buildVoiceInstructions();

    expect(wrapper.vm.agentForm.prompt).toContain(
      'Rol: Müşteri çağrıları için Destek asistanı'
    );
    expect(wrapper.vm.agentForm.prompt).toContain('Ton: Samimi');
    expect(wrapper.vm.agentForm.prompt).toContain(
      'İşletme bağlamı: Sipariş desteği'
    );
    expect(wrapper.vm.agentForm.prompt).toContain('Sınırlar: İade onayı verme');
    const prompt = wrapper.get('textarea[rows="16"]');
    expect(document.activeElement).toBe(prompt.element);
    expect(prompt.element.scrollIntoView).toHaveBeenCalledWith({
      behavior: 'smooth',
      block: 'nearest',
    });
    expect(wrapper.get('[aria-live="polite"]').text()).toContain(
      'Taslak Yönergeler alanına eklendi.'
    );
    await prompt.setValue('Kullanıcı tarafından düzenlendi');
    expect(wrapper.vm.agentForm.prompt).toBe('Kullanıcı tarafından düzenlendi');
    expect(wrapper.find('[aria-live="polite"]').exists()).toBe(false);
  });

  it('preserves manually edited instructions when draft replacement is cancelled', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    const prompt = wrapper.get('textarea[rows="16"]');
    await prompt.setValue('Keep this exact prompt');
    window.confirm.mockReturnValueOnce(false);

    await wrapper.vm.buildVoiceInstructions();

    expect(window.confirm).toHaveBeenCalledWith('Replace edited instructions?');
    expect(wrapper.vm.agentForm.prompt).toBe('Keep this exact prompt');
    expect(document.activeElement).not.toBe(prompt.element);
    expect(wrapper.find('[aria-live="polite"]').exists()).toBe(false);
  });

  it('replaces manually edited instructions after confirmation', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    const prompt = wrapper.get('textarea[rows="16"]');
    await prompt.setValue('Replace this prompt');
    window.confirm.mockReturnValueOnce(true);

    await wrapper.vm.buildVoiceInstructions();

    expect(window.confirm).toHaveBeenCalledOnce();
    expect(wrapper.vm.agentForm.prompt).toContain(
      'Role: You are VOICE_AI.DEFAULTS.AGENT_NAME for customer calls.'
    );
    expect(document.activeElement).toBe(prompt.element);
    await prompt.setValue('Editable final prompt');
    expect(wrapper.vm.agentForm.prompt).toBe('Editable final prompt');
  });

  it('never sends goal fields when creating or updating an assistant', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    wrapper.vm.agentForm.name = 'Assistant';
    await wrapper.vm.$nextTick();
    await wrapper.vm.saveVoiceAgent();

    expect(mocks.createAgent).toHaveBeenCalledOnce();
    expect(mocks.createAgent.mock.calls[0][0].authoring_profile).toEqual({
      tone: 'friendly',
      business_context: '',
      boundaries: '',
    });
    expect(mocks.createAgent.mock.calls[0][0]).not.toHaveProperty('goal');
    expect(mocks.createAgent.mock.calls[0][0]).not.toHaveProperty(
      'primary_goal'
    );

    wrapper.vm.editingVoiceAgentId = 9;
    wrapper.vm.voiceSetupProfile = {
      tone: 'concise',
      businessContext: 'Orders',
      boundaries: 'No refunds',
    };
    wrapper.vm.savedAgentSnapshot = 'outdated';
    await wrapper.vm.saveVoiceAgent();
    expect(mocks.updateAgent).toHaveBeenCalledOnce();
    expect(mocks.updateAgent.mock.calls[0][1].authoring_profile).toEqual({
      tone: 'concise',
      business_context: 'Orders',
      boundaries: 'No refunds',
    });
    expect(mocks.updateAgent.mock.calls[0][1]).not.toHaveProperty('goal');
    expect(mocks.updateAgent.mock.calls[0][1]).not.toHaveProperty(
      'primary_goal'
    );
  });
});
