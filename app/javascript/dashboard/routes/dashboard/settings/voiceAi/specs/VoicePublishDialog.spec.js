import { mount } from '@vue/test-utils';
import VoicePublishDialog from '../VoicePublishDialog.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) => {
      if (key.endsWith('.DESCRIPTION')) {
        return `Version ${values.version} of ${values.name}`;
      }
      return key;
    },
  }),
}));

const DialogStub = {
  props: ['title', 'description', 'confirmButtonLabel', 'isLoading'],
  emits: ['confirm'],
  methods: {
    open() {},
    close() {},
  },
  template: `
    <div>
      <p>{{ title }}</p>
      <p>{{ description }}</p>
      <slot />
      <button data-test="confirm" @click="$emit('confirm')">
        {{ confirmButtonLabel }}
      </button>
    </div>
  `,
};

const buildAgent = overrides => ({
  id: 8,
  name: 'Order assistant',
  enabled: false,
  published_revision: 2,
  inbox_settings: [
    { id: 3, inbox_id: 4, inbox_name: 'Phone support' },
    { id: 5, inbox_id: 6, inbox_name: 'Returns line' },
  ],
  readiness: {
    checks: [{ key: 'phone', complete: false, blocking: false }],
  },
  ...overrides,
});

const mountComponent = voiceAgent =>
  mount(VoicePublishDialog, {
    props: { voiceAgent },
    global: { stubs: { Dialog: DialogStub } },
  });

describe('VoicePublishDialog.vue', () => {
  it('defaults paused assistants to a paused publish and allows explicit activation', async () => {
    const wrapper = mountComponent(buildAgent());
    wrapper.vm.open();

    expect(wrapper.text()).toContain('Version 3 of Order assistant');
    expect(wrapper.text()).toContain('Phone support');
    expect(wrapper.text()).toContain('Returns line');
    expect(wrapper.text()).toContain('VOICE_AI.ROLLOUT.PHONE_MISSING');
    expect(wrapper.get('[role="switch"]').attributes('aria-checked')).toBe(
      'false'
    );

    await wrapper.get('[data-test="confirm"]').trigger('click');
    expect(wrapper.emitted('confirm').at(-1)).toEqual([{ activate: false }]);

    await wrapper.get('[role="switch"]').trigger('click');
    await wrapper.get('[data-test="confirm"]').trigger('click');
    expect(wrapper.emitted('confirm').at(-1)).toEqual([{ activate: true }]);
  });

  it('keeps an active assistant answering during an update', async () => {
    const wrapper = mountComponent(
      buildAgent({
        enabled: true,
        readiness: {
          checks: [{ key: 'phone', complete: true, blocking: false }],
        },
      })
    );
    wrapper.vm.open();

    expect(wrapper.find('[role="switch"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('VOICE_AI.ROLLOUT.ACTIVE_UPDATE');
    expect(wrapper.text()).toContain('VOICE_AI.ROLLOUT.PHONE_READY');

    await wrapper.get('[data-test="confirm"]').trigger('click');
    expect(wrapper.emitted('confirm')).toEqual([[{ activate: true }]]);
  });
});
