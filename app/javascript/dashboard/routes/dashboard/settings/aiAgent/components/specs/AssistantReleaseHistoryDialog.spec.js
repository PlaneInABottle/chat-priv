import { flushPromises, mount } from '@vue/test-utils';

import AssistantReleaseHistoryDialog from '../AssistantReleaseHistoryDialog.vue';

const mockUseAlert = vi.hoisted(() => vi.fn());
const mockTextApi = vi.hoisted(() => ({
  getReleases: vi.fn(),
  getRelease: vi.fn(),
  rollbackRelease: vi.fn(),
}));
const mockVoiceApi = vi.hoisted(() => ({
  getAgentReleases: vi.fn(),
  getAgentRelease: vi.fn(),
  rollbackAgentRelease: vi.fn(),
}));
const mockDialogClose = vi.hoisted(() => vi.fn());

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params = {}) =>
      params.version ? `${key}:${params.version}` : key,
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mockUseAlert,
}));

vi.mock('dashboard/api/aiAgent', () => ({ default: mockTextApi }));
vi.mock('dashboard/api/voice', () => ({ default: mockVoiceApi }));

const releases = [
  {
    id: 12,
    revision: 2,
    source: 'publish',
    created_at: '2026-07-11T12:00:00Z',
    created_by: { name: 'Alex' },
  },
  {
    id: 11,
    revision: 1,
    source: 'migration',
    created_at: '2026-07-10T12:00:00Z',
  },
];

const DialogStub = {
  name: 'Dialog',
  props: ['showConfirmButton', 'confirmButtonLabel'],
  emits: ['confirm'],
  template: `
    <div>
      <slot />
      <button
        v-if="showConfirmButton"
        data-testid="confirm-restore"
        @click="$emit('confirm')"
      >{{ confirmButtonLabel }}</button>
    </div>
  `,
  methods: {
    open() {},
    close: mockDialogClose,
  },
};

const mountComponent = (props = {}) =>
  mount(AssistantReleaseHistoryDialog, {
    props: {
      assistantType: 'text',
      assistantId: 42,
      currentReleaseId: 12,
      ...props,
    },
    global: {
      stubs: {
        Dialog: DialogStub,
        Button: {
          name: 'Button',
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

describe('AssistantReleaseHistoryDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockTextApi.getReleases.mockResolvedValue({ data: releases });
    mockTextApi.getRelease.mockResolvedValue({
      data: { ...releases[1], snapshot: { prompt: 'Original instructions' } },
    });
    mockTextApi.rollbackRelease.mockResolvedValue({ data: {} });
    mockVoiceApi.getAgentReleases.mockResolvedValue({ data: releases });
  });

  it('lists customer-facing versions and inspects a text snapshot', async () => {
    const wrapper = mountComponent();

    await wrapper.vm.open();
    await flushPromises();

    expect(mockTextApi.getReleases).toHaveBeenCalledWith(42);
    expect(wrapper.text()).toContain(
      'AI_ASSISTANT.RELEASE_HISTORY.SOURCE.PUBLISHED'
    );
    expect(wrapper.text()).not.toContain('migration');

    await wrapper.get('button[type="button"]:nth-of-type(1)').trigger('click');
    await flushPromises();

    expect(mockTextApi.getRelease).toHaveBeenCalledWith(42, 12);
    expect(wrapper.text()).toContain('Original instructions');
  });

  it('confirms rollback and reports that the assistant was restored', async () => {
    const wrapper = mountComponent();
    await wrapper.vm.open();
    await flushPromises();

    const restoreButton = wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('AI_ASSISTANT.RELEASE_HISTORY.RESTORE')
      );
    await restoreButton.trigger('click');
    await wrapper.get('[data-testid="confirm-restore"]').trigger('click');
    await flushPromises();

    expect(mockTextApi.rollbackRelease).toHaveBeenCalledWith(42, 11);
    expect(wrapper.emitted('restored')).toHaveLength(1);
    expect(mockDialogClose).toHaveBeenCalled();
  });

  it('uses the voice release API for voice assistants', async () => {
    const wrapper = mountComponent({ assistantType: 'voice' });

    await wrapper.vm.open();
    await flushPromises();

    expect(mockVoiceApi.getAgentReleases).toHaveBeenCalledWith(42);
    expect(mockTextApi.getReleases).not.toHaveBeenCalled();
  });
});
