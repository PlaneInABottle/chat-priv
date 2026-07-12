import { mount } from '@vue/test-utils';
import EvaluationQuality from '../components/EvaluationQuality.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) => {
      if (key.endsWith('.VERSION')) return `Version ${values.version}`;
      if (key.endsWith('.EVALUATION_SCORE')) {
        return `${values.passed} of ${values.total} passed (${values.rate}%)`;
      }
      if (key.endsWith('.HANDOFF_VALUE')) {
        return `${values.count} (${values.rate}%)`;
      }
      if (key.endsWith('.DRAFT')) return 'Current draft';
      if (key.endsWith('.LIVE')) return 'Live';
      if (key.endsWith('.CURRENT')) return 'Current version';

      return key;
    },
  }),
}));

describe('EvaluationQuality.vue', () => {
  it('shows draft evidence and real activity for each release', () => {
    const wrapper = mount(EvaluationQuality, {
      props: {
        quality: {
          draft: {
            differs_from_live: true,
            evaluation: { passed_count: 2, total_count: 2, pass_rate: 100 },
          },
          releases: [
            {
              id: 8,
              revision: 2,
              current: true,
              live: true,
              evaluation: {
                passed_count: 2,
                total_count: 3,
                pass_rate: 67,
              },
              activity: {
                conversations: 12,
                ai_replies: 20,
                handoffs: 3,
                handoff_rate: 25,
              },
            },
          ],
        },
      },
    });

    expect(wrapper.text()).toContain('Current draft');
    expect(wrapper.text()).toContain('2 of 2 passed (100%)');
    expect(wrapper.text()).toContain('Version 2');
    expect(wrapper.text()).toContain('Live');
    expect(wrapper.text()).toContain('2 of 3 passed (67%)');
    expect(wrapper.text()).toContain('12');
    expect(wrapper.text()).toContain('20');
    expect(wrapper.text()).toContain('3 (25%)');
  });

  it('does not duplicate the draft when it matches the live release', () => {
    const wrapper = mount(EvaluationQuality, {
      props: {
        quality: {
          draft: { differs_from_live: false },
          releases: [
            {
              id: 8,
              revision: 2,
              current: true,
              live: false,
              evaluation: null,
              activity: {
                conversations: 0,
                ai_replies: 0,
                handoffs: 0,
                handoff_rate: null,
              },
            },
          ],
        },
      },
    });

    expect(wrapper.text()).not.toContain('Current draft');
    expect(wrapper.text()).toContain('Version 2');
    expect(wrapper.text()).toContain('Current version');
    expect(wrapper.text()).toContain(
      'AI_ASSISTANT.EVALUATIONS.QUALITY.NOT_EVALUATED'
    );
  });
});
