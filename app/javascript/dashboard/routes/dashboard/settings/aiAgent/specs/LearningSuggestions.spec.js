import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import LearningSuggestions from '../components/LearningSuggestions.vue';

const apiMocks = vi.hoisted(() => ({
  get: vi.fn(),
  applySuggestion: vi.fn(),
  dismissSuggestion: vi.fn(),
}));

vi.mock('dashboard/api/aiAgentLearningSuggestions', () => ({
  default: class AiAgentLearningSuggestionsAPI {
    constructor() {
      Object.assign(this, apiMocks);
    }
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) =>
      key === 'AI_ASSISTANT.LEARNING.HISTORY'
        ? `Reviewed suggestions (${values.count})`
        : key,
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const readySuggestion = {
  id: 8,
  status: 'ready',
  destination: 'instructions',
  target_section: 'rules',
  source_name: null,
  customer_message: 'Will it arrive Tuesday?',
  human_answer: 'Delivery timing depends on the destination.',
  suggested_instruction: 'Do not promise an exact delivery date.',
  reason: 'This is reusable delivery guidance.',
  conversation_id: 12,
  source_message_id: 44,
  source_available: true,
};

const mountComponent = (props = {}) => {
  const refresh = vi.fn().mockResolvedValue({});
  const update = vi.fn().mockResolvedValue({ auto_learning_enabled: true });
  const store = createStore({
    getters: { getCurrentAccountId: () => 51 },
    actions: { 'aiAgent/refresh': refresh, 'aiAgent/update': update },
  });
  const wrapper = mount(LearningSuggestions, {
    props: { aiAgentId: 45, ...props },
    global: {
      plugins: [store],
      stubs: {
        Button: {
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
          props: ['label', 'disabled', 'isLoading'],
          emits: ['click'],
        },
        WootConfirmModal: {
          template: '<div />',
          methods: { showConfirmation: () => Promise.resolve(true) },
        },
      },
    },
  });

  return { wrapper, refresh, update };
};

describe('LearningSuggestions.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    apiMocks.get.mockResolvedValue({ data: [] });
  });

  it('shows the human evidence and editable proposed instruction', async () => {
    apiMocks.get.mockResolvedValue({ data: [readySuggestion] });
    const { wrapper } = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('Will it arrive Tuesday?');
    expect(wrapper.text()).toContain(
      'Delivery timing depends on the destination.'
    );
    expect(wrapper.find('textarea').element.value).toBe(
      'Do not promise an exact delivery date.'
    );
    expect(wrapper.find('[name="learning-destination-8"]').element.value).toBe(
      'instructions'
    );
    expect(wrapper.find('[name="learning-section-8"]').element.value).toBe(
      'rules'
    );
    expect(wrapper.find('a').attributes('href')).toContain(
      '/app/accounts/51/conversations/12?messageId=44'
    );
  });

  it('enables automatic review of resolved handoffs', async () => {
    const { wrapper, update } = mountComponent();
    await flushPromises();

    await wrapper.find('[role="switch"]').trigger('click');
    await flushPromises();

    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 45,
      data: { auto_learning_enabled: true },
    });
  });

  it('applies the reviewed text to the selected draft section', async () => {
    apiMocks.get.mockResolvedValue({ data: [readySuggestion] });
    apiMocks.applySuggestion.mockResolvedValue({
      data: { ...readySuggestion, status: 'applied' },
    });
    const { wrapper, refresh } = mountComponent();
    await flushPromises();

    await wrapper
      .find('textarea')
      .setValue(
        'Never promise a delivery date before checking the destination.'
      );
    await wrapper
      .find('[name="learning-section-8"]')
      .setValue('business_context');
    const applyButton = wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('AI_ASSISTANT.LEARNING.APPLY_TO_DRAFT')
      );
    await applyButton.trigger('click');
    await flushPromises();

    expect(apiMocks.applySuggestion).toHaveBeenCalledWith(8, {
      suggested_instruction:
        'Never promise a delivery date before checking the destination.',
      destination: 'instructions',
      target_section: 'business_context',
      source_name: '',
    });
    expect(refresh).toHaveBeenCalledOnce();
    expect(wrapper.emitted('draftUpdated')).toHaveLength(1);
    expect(wrapper.text()).toContain('Reviewed suggestions (1)');
  });

  it('applies reviewed facts without overwriting unsaved instructions', async () => {
    const knowledgeSuggestion = {
      ...readySuggestion,
      destination: 'knowledge',
      target_section: null,
      source_name: 'Returns policy',
      suggested_instruction: 'Returns are accepted within 14 days.',
    };
    apiMocks.get.mockResolvedValue({ data: [knowledgeSuggestion] });
    apiMocks.applySuggestion.mockResolvedValue({
      data: {
        ...knowledgeSuggestion,
        status: 'applied',
        ai_knowledge_source_id: 19,
      },
    });
    const { wrapper, refresh } = mountComponent({
      hasUnsavedInstructions: true,
    });
    await flushPromises();

    await wrapper
      .find('[name="learning-source-name-8"]')
      .setValue('Returns and exchanges');
    const applyButton = wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('AI_ASSISTANT.LEARNING.ADD_TO_KNOWLEDGE')
      );
    await applyButton.trigger('click');
    await flushPromises();

    expect(apiMocks.applySuggestion).toHaveBeenCalledWith(8, {
      suggested_instruction: 'Returns are accepted within 14 days.',
      destination: 'knowledge',
      target_section: null,
      source_name: 'Returns and exchanges',
    });
    expect(refresh).toHaveBeenCalledOnce();
    expect(wrapper.emitted('draftUpdated')).toEqual([
      [{ preserveInstructions: true }],
    ]);
  });

  it('selects a valid section when changing knowledge to instructions', async () => {
    const knowledgeSuggestion = {
      ...readySuggestion,
      destination: 'knowledge',
      target_section: null,
      source_name: 'Delivery policy',
    };
    apiMocks.get.mockResolvedValue({ data: [knowledgeSuggestion] });
    const { wrapper } = mountComponent();
    await flushPromises();

    await wrapper
      .find('[name="learning-destination-8"]')
      .setValue('instructions');

    expect(wrapper.find('[name="learning-section-8"]').element.value).toBe(
      'additional'
    );
  });

  it('does not overwrite unsaved instruction edits', async () => {
    apiMocks.get.mockResolvedValue({ data: [readySuggestion] });
    const { wrapper } = mountComponent({ hasUnsavedInstructions: true });
    await flushPromises();

    const applyButton = wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('AI_ASSISTANT.LEARNING.APPLY_TO_DRAFT')
      );
    expect(applyButton.attributes('disabled')).toBeDefined();

    await wrapper.vm.applySuggestion(readySuggestion);

    expect(apiMocks.applySuggestion).not.toHaveBeenCalled();
  });

  it('keeps not-recommended items in reviewed history', async () => {
    apiMocks.get.mockResolvedValue({
      data: [
        {
          ...readySuggestion,
          status: 'not_recommended',
          suggested_instruction: null,
          reason: 'This answer contains customer-specific order details.',
        },
      ],
    });
    const { wrapper } = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('Reviewed suggestions (1)');
    expect(wrapper.text()).toContain(
      'This answer contains customer-specific order details.'
    );
  });
});
