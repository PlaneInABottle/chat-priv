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
  target_section: 'rules',
  customer_message: 'Will it arrive Tuesday?',
  human_answer: 'Delivery timing depends on the destination.',
  suggested_instruction: 'Do not promise an exact delivery date.',
  reason: 'This is reusable delivery guidance.',
  conversation_id: 12,
  source_message_id: 44,
  source_available: true,
};

const mountComponent = () => {
  const refresh = vi.fn().mockResolvedValue({});
  const store = createStore({
    getters: { getCurrentAccountId: () => 51 },
    actions: { 'aiAgent/refresh': refresh },
  });
  const wrapper = mount(LearningSuggestions, {
    props: { aiAgentId: 45 },
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

  return { wrapper, refresh };
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
    expect(wrapper.find('select').element.value).toBe('rules');
    expect(wrapper.find('a').attributes('href')).toContain(
      '/app/accounts/51/conversations/12?messageId=44'
    );
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
    await wrapper.find('select').setValue('business_context');
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
      target_section: 'business_context',
    });
    expect(refresh).toHaveBeenCalledOnce();
    expect(wrapper.text()).toContain('Reviewed suggestions (1)');
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
