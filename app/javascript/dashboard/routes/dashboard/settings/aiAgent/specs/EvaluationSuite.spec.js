import { flushPromises, mount } from '@vue/test-utils';
import EvaluationSuite from '../components/EvaluationSuite.vue';

const apiMocks = vi.hoisted(() => ({
  get: vi.fn(),
  create: vi.fn(),
  updateCase: vi.fn(),
  deleteCase: vi.fn(),
  getRuns: vi.fn(),
  getRun: vi.fn(),
  createRun: vi.fn(),
}));

vi.mock('dashboard/api/aiAgentEvaluations', () => ({
  default: class AiAgentEvaluationsAPI {
    constructor() {
      Object.assign(this, apiMocks);
    }
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) =>
      key === 'AI_ASSISTANT.EVALUATIONS.RUN.SUMMARY'
        ? `${values.passed} of ${values.total} scenarios passed`
        : key,
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const evaluationCase = {
  id: 7,
  name: 'Delivery question',
  customer_message: 'When will it arrive?',
  success_criteria: 'Do not promise an exact date.',
  position: 1,
  created_at: '2026-07-10T10:00:00Z',
  updated_at: '2026-07-10T10:00:00Z',
};

const completedRun = {
  id: 3,
  status: 'completed',
  total_count: 1,
  passed_count: 1,
  current_draft: true,
  created_at: '2026-07-10T11:00:00Z',
  results: [
    {
      id: 9,
      evaluation_case_id: 7,
      status: 'completed',
      passed: true,
      assistant_response: 'Delivery depends on your location.',
      reason: 'The response avoids an exact promise.',
    },
  ],
};

const mountComponent = (props = {}) =>
  mount(EvaluationSuite, {
    props: { aiAgentId: 43, ...props },
    global: {
      stubs: {
        Button: {
          template:
            '<button :type="type || \'button\'" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
          props: ['label', 'disabled', 'type'],
          emits: ['click'],
        },
        WootConfirmModal: {
          template: '<div />',
          methods: { showConfirmation: () => Promise.resolve(true) },
        },
      },
    },
  });

describe('EvaluationSuite.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    apiMocks.get.mockResolvedValue({ data: [] });
    apiMocks.getRuns.mockResolvedValue({ data: [] });
  });

  it('shows saved scenarios with current draft evidence', async () => {
    apiMocks.get.mockResolvedValue({ data: [evaluationCase] });
    apiMocks.getRuns.mockResolvedValue({ data: [completedRun] });

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('Delivery question');
    expect(wrapper.text()).toContain('Delivery depends on your location.');
    expect(wrapper.text()).toContain('The response avoids an exact promise.');
    expect(wrapper.text()).toContain('AI_ASSISTANT.EVALUATIONS.RESULT.PASSED');
  });

  it('keeps evidence visible while marking results from an older draft', async () => {
    apiMocks.get.mockResolvedValue({ data: [evaluationCase] });
    apiMocks.getRuns.mockResolvedValue({
      data: [{ ...completedRun, current_draft: false }],
    });

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('Delivery depends on your location.');
    expect(wrapper.text()).toContain(
      'AI_ASSISTANT.EVALUATIONS.RESULT.OLDER_DRAFT'
    );
  });

  it('does not show mismatched evidence after a scenario is edited', async () => {
    apiMocks.get.mockResolvedValue({
      data: [{ ...evaluationCase, updated_at: '2026-07-10T12:00:00Z' }],
    });
    apiMocks.getRuns.mockResolvedValue({ data: [completedRun] });

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('AI_ASSISTANT.EVALUATIONS.RESULT.CHANGED');
    expect(wrapper.text()).not.toContain('Delivery depends on your location.');
  });

  it('creates a scenario from the plain-language form', async () => {
    apiMocks.create.mockResolvedValue({ data: evaluationCase });
    const wrapper = mountComponent();
    await flushPromises();

    wrapper.vm.openCreateForm();
    wrapper.vm.form = {
      name: ' Delivery question ',
      customer_message: ' When will it arrive? ',
      success_criteria: ' Do not promise an exact date. ',
    };
    await wrapper.vm.saveCase();

    expect(apiMocks.create).toHaveBeenCalledWith({
      name: 'Delivery question',
      customer_message: 'When will it arrive?',
      success_criteria: 'Do not promise an exact date.',
    });
    expect(wrapper.vm.evaluationCases).toEqual([evaluationCase]);
  });

  it('starts one asynchronous run for the current suite', async () => {
    apiMocks.get.mockResolvedValue({ data: [evaluationCase] });
    apiMocks.createRun.mockResolvedValue({
      data: {
        id: 4,
        status: 'pending',
        current_draft: true,
        results: [],
      },
    });
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.vm.startRun();

    expect(apiMocks.createRun).toHaveBeenCalledOnce();
    expect(wrapper.vm.latestRun.id).toBe(4);
    expect(wrapper.vm.isRunActive).toBe(true);
    wrapper.unmount();
  });

  it('does not run a saved draft while instruction edits are unsaved', async () => {
    apiMocks.get.mockResolvedValue({ data: [evaluationCase] });
    const wrapper = mountComponent({ hasUnsavedInstructions: true });
    await flushPromises();

    const runButton = wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('AI_ASSISTANT.EVALUATIONS.RUN.ACTION')
      );
    expect(runButton.attributes('disabled')).toBeDefined();

    await wrapper.vm.startRun();

    expect(apiMocks.createRun).not.toHaveBeenCalled();
  });
});
