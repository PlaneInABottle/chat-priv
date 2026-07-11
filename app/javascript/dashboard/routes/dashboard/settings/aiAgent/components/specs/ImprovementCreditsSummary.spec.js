import { flushPromises, mount } from '@vue/test-utils';

import ImprovementCreditsSummary from '../ImprovementCreditsSummary.vue';

const mockApi = vi.hoisted(() => ({ get: vi.fn() }));
const mockUseAlert = vi.hoisted(() => vi.fn());

vi.mock('dashboard/api/aiImprovementUsage', () => ({ default: mockApi }));
vi.mock('dashboard/composables', () => ({ useAlert: mockUseAlert }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params = {}) =>
      params.remaining === undefined
        ? key
        : `${params.remaining}/${params.limit}/${params.date}`,
  }),
}));

const usage = {
  limit_credits: 10,
  used_credits: 2,
  reserved_credits: 1,
  remaining_credits: 7,
  unlimited: false,
  status: 'ok',
  reset_at: '2026-08-01T00:00:00Z',
};

describe('ImprovementCreditsSummary', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockApi.get.mockResolvedValue({ data: usage });
  });

  it('shows remaining credits and includes reservations in progress', async () => {
    const wrapper = mount(ImprovementCreditsSummary);
    await flushPromises();

    expect(wrapper.text()).toContain('7/10/');
    expect(wrapper.get('[role="progressbar"]').attributes()).toMatchObject({
      'aria-valuenow': '3',
      'aria-valuemax': '10',
    });
    expect(
      wrapper.get('[role="progressbar"]').attributes('aria-label')
    ).toContain('7/10/');
    expect(
      wrapper.get('[role="progressbar"] > div').attributes('style')
    ).toContain('width: 30%');
    expect(wrapper.emitted('loaded')).toEqual([[usage]]);
  });

  it('hides the progress bar for an unlimited account', async () => {
    mockApi.get.mockResolvedValue({
      data: {
        ...usage,
        limit_credits: 0,
        remaining_credits: null,
        unlimited: true,
        status: 'unlimited',
      },
    });

    const wrapper = mount(ImprovementCreditsSummary);
    await flushPromises();

    expect(wrapper.text()).toContain(
      'AI_ASSISTANT.IMPROVEMENT_CREDITS.UNLIMITED'
    );
    expect(wrapper.find('[role="progressbar"]').exists()).toBe(false);
  });

  it('shows a safe error when usage cannot be loaded', async () => {
    mockApi.get.mockRejectedValue(new Error('network failure'));

    mount(ImprovementCreditsSummary);
    await flushPromises();

    expect(mockUseAlert).toHaveBeenCalledWith(
      'AI_ASSISTANT.IMPROVEMENT_CREDITS.LOAD_ERROR'
    );
  });
});
