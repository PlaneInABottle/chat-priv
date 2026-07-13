import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';

import SettingsWrapper from './SettingsWrapper.vue';

const routeState = vi.hoisted(() => ({ route: null }));

vi.mock('vue-router', async importOriginal => {
  const { reactive } = await import('vue');
  routeState.route = reactive({
    fullPath: '/app/accounts/51/settings/ai-assistants/43/instructions',
    meta: { keepAliveKey: 'ai-agent-detail' },
    params: { id: '43' },
  });

  return {
    ...(await importOriginal()),
    useRoute: () => routeState.route,
  };
});

describe('SettingsWrapper.vue', () => {
  it('keeps one view instance across routes with the same scoped cache key', async () => {
    const wrapper = mount(SettingsWrapper, {
      global: { stubs: { RouterView: true } },
    });

    expect(wrapper.classes()).toEqual(
      expect.arrayContaining(['pb-24', 'md:pb-8'])
    );
    expect(wrapper.vm.viewKey).toBe('ai-agent-detail:43');

    routeState.route.fullPath =
      '/app/accounts/51/settings/ai-assistants/43/evaluations';
    await nextTick();

    expect(wrapper.vm.viewKey).toBe('ai-agent-detail:43');

    routeState.route.params.id = '45';
    await nextTick();

    expect(wrapper.vm.viewKey).toBe('ai-agent-detail:45');
  });
});
