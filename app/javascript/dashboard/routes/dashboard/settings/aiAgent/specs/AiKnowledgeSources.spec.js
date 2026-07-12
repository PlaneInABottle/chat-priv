/* eslint-disable vue/one-component-per-file -- local stubs keep this page spec focused */
import { defineComponent, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';

import AiKnowledgeSources from '../AiKnowledgeSources.vue';

const api = vi.hoisted(() => ({
  get: vi.fn(),
  show: vi.fn(),
  create: vi.fn(),
  update: vi.fn(),
  delete: vi.fn(),
  sync: vi.fn(),
}));

vi.mock('dashboard/api/aiKnowledgeSources', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const SettingsLayout = defineComponent({
  template: '<div><slot name="header" /><slot name="body" /></div>',
});
const BaseSettingsHeader = defineComponent({
  template: '<header><slot name="actions" /></header>',
});
const Button = defineComponent({
  props: { label: { type: String, default: '' } },
  emits: ['click'],
  setup(props, { emit }) {
    return () =>
      h(
        'button',
        { type: 'button', onClick: () => emit('click') },
        props.label
      );
  },
});
const Dialog = defineComponent({
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /></div>',
});
const Input = defineComponent({
  props: { modelValue: { type: String, default: '' } },
  emits: ['update:modelValue'],
  setup(props, { emit }) {
    return () =>
      h('input', {
        value: props.modelValue,
        onInput: event => emit('update:modelValue', event.target.value),
      });
  },
});

const mountComponent = async (sourceData = []) => {
  api.get.mockResolvedValue({ data: sourceData });
  const wrapper = mount(AiKnowledgeSources, {
    global: {
      stubs: { SettingsLayout, BaseSettingsHeader, Button, Dialog, Input },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('AiKnowledgeSources', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows website identity and failed freshness state', async () => {
    const wrapper = await mountComponent([
      {
        id: 3,
        name: 'Store policies',
        source_type: 'website',
        website_url: 'https://example.com/policies',
        sync_status: 'failed',
        sync_error: 'Website unavailable',
        content_preview: 'Last-known-good policy',
        character_count: 22,
        assigned_ai_agent_ids: [],
        assigned_voice_agent_ids: [],
        last_synced_at: '2026-07-11T12:00:00Z',
        updated_at: '2026-07-11T12:00:00Z',
      },
    ]);

    expect(wrapper.text()).toContain('Store policies');
    expect(wrapper.text()).toContain('https://example.com/policies');
    expect(wrapper.text()).toContain('AI_KNOWLEDGE.STATUS.FAILED');
    wrapper.unmount();
  });

  it('creates website sources without accepting editable synced content', async () => {
    const wrapper = await mountComponent();
    api.create.mockResolvedValue({
      data: {
        id: 8,
        name: 'Website policies',
        source_type: 'website',
        website_url: 'https://example.com/',
        sync_status: 'pending',
      },
    });
    wrapper.vm.openCreate();
    wrapper.vm.form.source_type = 'website';
    wrapper.vm.form.name = 'Website policies';
    wrapper.vm.form.website_url = 'example.com';
    wrapper.vm.form.content = 'This must not be submitted';

    await wrapper.vm.saveSource();

    expect(api.create).toHaveBeenCalledWith({
      name: 'Website policies',
      source_type: 'website',
      website_url: 'example.com',
    });
    wrapper.unmount();
  });

  it('queues an explicit website resync', async () => {
    const source = {
      id: 4,
      name: 'Returns',
      source_type: 'website',
      sync_status: 'ready',
      available: true,
      content_preview: 'Returns within 14 days.',
      character_count: 23,
      assigned_ai_agent_ids: [],
      assigned_voice_agent_ids: [],
      last_synced_at: '2026-07-11T12:00:00Z',
      updated_at: '2026-07-11T12:00:00Z',
    };
    const wrapper = await mountComponent([source]);
    api.sync.mockResolvedValue({ data: { ...source, sync_status: 'pending' } });

    await wrapper.vm.syncSource(source);

    expect(api.sync).toHaveBeenCalledWith(source.id);
    expect(wrapper.vm.sources[0].sync_status).toBe('pending');
    wrapper.unmount();
  });
});
