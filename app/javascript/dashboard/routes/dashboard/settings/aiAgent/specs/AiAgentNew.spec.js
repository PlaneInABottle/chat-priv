import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';

import AiAgentNew from '../AiAgentNew.vue';

const routerPush = vi.fn();

vi.mock('vue-router', async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    useRouter: () => ({ push: routerPush }),
  };
});

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const InputStub = {
  props: ['modelValue', 'label', 'placeholder', 'message', 'messageType'],
  emits: ['update:modelValue', 'input'],
  template: `
    <label>
      {{ label }}
      <input
        :value="modelValue"
        :placeholder="placeholder"
        @input="$emit('update:modelValue', $event.target.value); $emit('input', $event)"
      />
      <p v-if="message" :data-message-type="messageType">{{ message }}</p>
    </label>
  `,
};

const ButtonStub = {
  props: ['label', 'type', 'disabled', 'isLoading'],
  emits: ['click'],
  template: `
    <button :type="type" :disabled="disabled || isLoading" @click="$emit('click')">
      {{ label }}
    </button>
  `,
};

const mountComponent = createResult => {
  const store = createStore({
    getters: {
      'aiAgent/getUIFlags': () => ({ isCreating: false }),
    },
    actions: {
      'aiAgent/create': vi.fn().mockResolvedValue(createResult),
    },
  });

  const wrapper = mount(AiAgentNew, {
    global: {
      plugins: [store],
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
        },
        BaseSettingsHeader: { template: '<div />' },
        Button: ButtonStub,
        Input: InputStub,
      },
    },
  });

  return { wrapper, store };
};

describe('AiAgentNew.vue', () => {
  beforeEach(() => {
    routerPush.mockClear();
  });

  it('renders blank-name validation errors through the Input message API', async () => {
    const { wrapper } = mountComponent();

    await wrapper.find('form').trigger('submit');

    const input = wrapper.findComponent(InputStub);
    expect(input.props('message')).toBe('AI_AGENTS.NEW.NAME_REQUIRED');
    expect(input.props('messageType')).toBe('error');
    expect(wrapper.text()).toContain('AI_AGENTS.NEW.NAME_REQUIRED');
  });

  it('renders create API errors through the Input message API', async () => {
    const { wrapper } = mountComponent({ error: 'Name already exists' });

    await wrapper.find('input').setValue('Support bot');
    await wrapper.find('form').trigger('submit');

    const input = wrapper.findComponent(InputStub);
    expect(input.props('message')).toBe('Name already exists');
    expect(input.props('messageType')).toBe('error');
    expect(wrapper.text()).toContain('Name already exists');
  });
});
