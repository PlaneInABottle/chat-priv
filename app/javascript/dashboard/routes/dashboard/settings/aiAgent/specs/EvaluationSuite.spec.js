import { flushPromises, mount } from '@vue/test-utils';
import EvaluationSuite from '../components/EvaluationSuite.vue';

const apiMocks = vi.hoisted(() => ({
  get: vi.fn(),
  create: vi.fn(),
  updateCase: vi.fn(),
  deleteCase: vi.fn(),
  generateCases: vi.fn(),
  getGeneration: vi.fn(),
  getRuns: vi.fn(),
  getQuality: vi.fn(),
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
  needs_review: false,
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
    apiMocks.getQuality.mockResolvedValue({
      data: { draft: { differs_from_live: false }, releases: [] },
    });
    apiMocks.getGeneration.mockResolvedValue({ data: {} });
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

  it('keeps scenarios available when version quality cannot load', async () => {
    apiMocks.get.mockResolvedValue({ data: [evaluationCase] });
    apiMocks.getQuality.mockRejectedValue(new Error('Unavailable'));

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('Delivery question');
    expect(wrapper.vm.quality).toBeNull();
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

  it('starts suggested scenario generation without blocking the workspace', async () => {
    apiMocks.generateCases.mockResolvedValue({
      data: { id: 12, status: 'pending', requested_count: 5 },
    });
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.vm.generateCases();

    expect(apiMocks.generateCases).toHaveBeenCalledOnce();
    expect(wrapper.vm.generation).toMatchObject({ id: 12, status: 'pending' });
    expect(wrapper.vm.evaluationCases).toEqual([]);
    expect(wrapper.emitted('usageChanged')).toBeUndefined();
    wrapper.unmount();
  });

  it('loads generated scenarios when background generation completes', async () => {
    apiMocks.getGeneration.mockResolvedValueOnce({
      data: { id: 12, status: 'running', requested_count: 5 },
    });
    const wrapper = mountComponent();
    await flushPromises();
    apiMocks.getGeneration.mockResolvedValue({
      data: { id: 12, status: 'completed', created_count: 1 },
    });
    apiMocks.get.mockResolvedValue({
      data: [{ ...evaluationCase, needs_review: true }],
    });

    await wrapper.vm.refreshGeneration();

    expect(wrapper.vm.evaluationCases).toEqual([
      { ...evaluationCase, needs_review: true },
    ]);
    expect(wrapper.emitted('usageChanged')).toHaveLength(1);
    wrapper.unmount();
  });

  it('requires explicit approval before a suggested scenario can run', async () => {
    const suggestedCase = { ...evaluationCase, needs_review: true };
    apiMocks.get.mockResolvedValue({ data: [suggestedCase] });
    apiMocks.updateCase.mockResolvedValue({ data: evaluationCase });
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.vm.reviewedCases).toEqual([]);
    await wrapper.vm.approveCase(suggestedCase);

    expect(apiMocks.updateCase).toHaveBeenCalledWith(suggestedCase.id, {});
    expect(wrapper.vm.reviewedCases).toEqual([evaluationCase]);
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

  it('keeps scenarios editable but blocks a run when credits are exhausted', async () => {
    apiMocks.get.mockResolvedValue({ data: [evaluationCase] });
    const wrapper = mountComponent({ creditsExhausted: true });
    await flushPromises();

    const buttons = wrapper.findAll('button');
    const runButton = buttons.find(button =>
      button.text().includes('AI_ASSISTANT.EVALUATIONS.RUN.ACTION')
    );
    const addButton = buttons.find(button =>
      button.text().includes('AI_ASSISTANT.EVALUATIONS.ADD')
    );
    const suggestButton = buttons.find(button =>
      button.text().includes('AI_ASSISTANT.EVALUATIONS.GENERATE.ACTION')
    );
    expect(runButton.attributes('disabled')).toBeDefined();
    expect(suggestButton.attributes('disabled')).toBeDefined();
    expect(addButton.attributes('disabled')).toBeUndefined();

    await wrapper.vm.startRun();

    expect(apiMocks.createRun).not.toHaveBeenCalled();
  });
});
