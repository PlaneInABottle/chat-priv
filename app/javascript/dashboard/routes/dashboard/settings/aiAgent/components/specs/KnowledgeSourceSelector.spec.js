import { flushPromises, mount } from '@vue/test-utils';

import KnowledgeSourceSelector from '../KnowledgeSourceSelector.vue';

const api = vi.hoisted(() => ({ get: vi.fn() }));
const push = vi.hoisted(() => vi.fn());

vi.mock('dashboard/api/aiKnowledgeSources', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

describe('KnowledgeSourceSelector', () => {
  it('prevents selecting a website source before readable content exists', async () => {
    api.get.mockResolvedValue({
      data: [
        {
          id: 1,
          name: 'Pending website',
          available: false,
          content_preview: '',
          character_count: 0,
        },
        {
          id: 2,
          name: 'Ready policy',
          available: true,
          content_preview: 'Returns within 14 days.',
          character_count: 23,
        },
      ],
    });
    const wrapper = mount(KnowledgeSourceSelector);
    await flushPromises();

    const pendingInput = wrapper.get('[data-testid="knowledge-source-1"]');
    const readyInput = wrapper.get('[data-testid="knowledge-source-2"]');
    expect(pendingInput.attributes('disabled')).toBeDefined();
    expect(readyInput.attributes('disabled')).toBeUndefined();

    await readyInput.setValue(true);

    expect(wrapper.emitted('update:modelValue')).toEqual([[[2]]]);
  });
});
