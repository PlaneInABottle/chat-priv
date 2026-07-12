import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';

import AiAgentList from '../AiAgentList.vue';

vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRouter: () => ({ push: vi.fn() }),
}));

describe('AiAgentList.vue', () => {
  it('keeps cached assistants visible while refreshing the list', () => {
    const store = createStore({
      state: {
        agents: [{ id: 42, name: 'Support assistant' }],
      },
      getters: {
        'aiAgent/getAiAgents': state => state.agents,
      },
      actions: {
        'aiAgent/get': () => new Promise(() => {}),
      },
    });
    const wrapper = mount(AiAgentList, {
      global: {
        plugins: [store],
        stubs: {
          SettingsLayout: {
            props: ['isLoading'],
            template:
              '<div :data-loading="isLoading"><slot name="header" /><slot name="body" /></div>',
          },
          BaseSettingsHeader: {
            template: '<div><slot name="actions" /></div>',
          },
          AiAgentListItem: {
            props: ['agent'],
            template: '<div>{{ agent.name }}</div>',
          },
          Button: { template: '<button />' },
          Dialog: { template: '<div />' },
        },
      },
    });

    expect(wrapper.vm.isInitialLoading).toBe(false);
    expect(wrapper.text()).toContain('Support assistant');
  });
});
