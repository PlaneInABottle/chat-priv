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
    const wrapper = mount(KnowledgeSourceSelector, {
      global: {
        stubs: {
          Dialog: {
            name: 'Dialog',
            emits: ['confirm'],
            template:
              '<div><slot /><button data-testid="apply-selection" @click="$emit(\'confirm\')">Apply</button></div>',
            methods: { open() {}, close() {} },
          },
          Button: {
            props: ['label'],
            emits: ['click'],
            template: '<button @click="$emit(\'click\')">{{ label }}</button>',
          },
        },
      },
    });
    await flushPromises();
    await wrapper.vm.openPicker();
    await wrapper.vm.$nextTick();

    expect(wrapper.get('input[type="search"]').attributes()).toMatchObject({
      'aria-label': 'AI_KNOWLEDGE.SELECTOR.SEARCH',
      name: 'knowledge-source-search',
    });
    expect(wrapper.text()).toContain('AI_KNOWLEDGE.ACTIONS.MANAGE');
    const pendingInput = wrapper.get('[data-testid="knowledge-source-1"]');
    const readyInput = wrapper.get('[data-testid="knowledge-source-2"]');
    expect(pendingInput.attributes('disabled')).toBeDefined();
    expect(readyInput.attributes('disabled')).toBeUndefined();

    await readyInput.setValue(true);
    await wrapper.get('[data-testid="apply-selection"]').trigger('click');

    expect(wrapper.emitted('update:modelValue')).toEqual([[[2]]]);
  });
});
