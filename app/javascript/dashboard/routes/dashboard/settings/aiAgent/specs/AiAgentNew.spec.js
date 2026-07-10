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
    state: { inboxes: [] },
    getters: {
      'aiAgent/getUIFlags': () => ({ isCreating: false }),
      'inboxes/getInboxes': state => state.inboxes,
    },
    actions: {
      'aiAgent/create': vi.fn().mockResolvedValue(createResult),
      'inboxes/get': vi.fn().mockResolvedValue([]),
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

  it('shows a blank-name validation error before continuing', async () => {
    const { wrapper } = mountComponent();

    wrapper.vm.nextStep();
    await wrapper.vm.$nextTick();

    const alert = wrapper.find('[role="alert"]');
    expect(alert.text()).toBe('AI_AGENTS.NEW.NAME_REQUIRED');
    expect(wrapper.vm.currentStep).toBe(0);
  });

  it('shows create API errors on the review step', async () => {
    const { wrapper } = mountComponent({ error: 'Name already exists' });

    wrapper.vm.form.name = 'Support bot';
    wrapper.vm.form.instructions = 'Help customers.';
    wrapper.vm.form.inboxIds = [1];
    wrapper.vm.currentStep = 3;
    await wrapper.vm.handleSubmit();
    await wrapper.vm.$nextTick();

    expect(wrapper.find('[role="alert"]').text()).toBe('Name already exists');
  });
});
