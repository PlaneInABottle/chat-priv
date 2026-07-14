import { flushPromises, mount } from '@vue/test-utils';

import WebsiteImportStatus from '../WebsiteImportStatus.vue';

const mockUseAlert = vi.hoisted(() => vi.fn());
const mockApi = vi.hoisted(() => ({
  get: vi.fn(),
  dismiss: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mockUseAlert,
}));

vi.mock('dashboard/api/aiAgentWebsiteImports', () => ({
  default: class {
    get = mockApi.get;

    dismiss = mockApi.dismiss;
  },
}));

const readyImport = {
  id: 7,
  status: 'ready',
  stage: 'complete',
  website_url: 'https://example.com/',
  proposed_sections: {
    identity: 'Represent Example.',
    rules: 'Use verified facts.',
  },
  source_count: 3,
};

const mountComponent = (props = {}) =>
  mount(WebsiteImportStatus, {
    props: {
      aiAgentId: 42,
      currentDocument: { version: 4, sections: {} },
      expectedDraftFingerprint: 'loaded-fingerprint',
      ...props,
    },
    global: {
      stubs: {
        Button: {
          props: ['label'],
          template: '<button>{{ label }}</button>',
        },
        Icon: true,
        Spinner: true,
        WebsiteImportDialog: {
          template: '<div />',
          methods: { open() {} },
        },
      },
    },
  });

describe('WebsiteImportStatus', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockApi.get.mockResolvedValue({ data: [readyImport] });
    mockApi.dismiss.mockResolvedValue({ data: {} });
  });

  it('announces a ready review and reports its suggestion count', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.vm.isReady).toBe(true);
    expect(wrapper.emitted('readyCountChanged').at(-1)).toEqual([2]);
    expect(mockUseAlert).toHaveBeenCalledWith(
      'AI_ASSISTANT.WEBSITE_IMPORT.READY_TO_REVIEW'
    );
  });

  it('clears terminal imports after an apply event', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    wrapper.vm.handleStateChanged({ ...readyImport, status: 'applied' });
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.latestImport).toBeNull();
    expect(wrapper.emitted('readyCountChanged').at(-1)).toEqual([0]);
  });

  it('updates the count when the local instruction draft changes', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.setProps({
      currentDocument: {
        version: 4,
        sections: { identity: 'Represent Example.' },
      },
    });

    expect(wrapper.emitted('readyCountChanged').at(-1)).toEqual([1]);
  });

  it('keeps suggestions visible and reports a dismiss failure', async () => {
    mockApi.dismiss.mockRejectedValue(new Error('network'));
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.vm.dismissReady();

    expect(wrapper.vm.isReady).toBe(true);
    expect(mockUseAlert).toHaveBeenCalledWith(
      'AI_ASSISTANT.WEBSITE_IMPORT.ERROR.DISMISS'
    );
  });

  it('does not show a website with no reusable output as ready knowledge', async () => {
    mockApi.get.mockResolvedValue({
      data: [
        {
          ...readyImport,
          proposed_sections: {},
          knowledge_available: false,
        },
      ],
    });
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'AI_ASSISTANT.WEBSITE_IMPORT.READY_NO_CHANGES_TITLE'
    );
    expect(wrapper.text()).toContain(
      'AI_ASSISTANT.WEBSITE_IMPORT.STATUS_READY_NO_CHANGES_HELP'
    );
    expect(wrapper.text()).toContain('AI_ASSISTANT.WEBSITE_IMPORT.TRY_AGAIN');
    expect(mockUseAlert).not.toHaveBeenCalled();
  });

  it('ignores a late response after switching assistants', async () => {
    let resolveFirstRequest;
    mockApi.get
      .mockReturnValueOnce(
        new Promise(resolve => {
          resolveFirstRequest = resolve;
        })
      )
      .mockResolvedValueOnce({
        data: [{ ...readyImport, id: 9, website_url: 'https://new.example/' }],
      });
    const wrapper = mountComponent();

    await wrapper.setProps({ aiAgentId: 43 });
    await flushPromises();
    expect(wrapper.vm.latestImport.id).toBe(9);

    resolveFirstRequest({ data: [{ ...readyImport, id: 7 }] });
    await flushPromises();

    expect(wrapper.vm.latestImport.id).toBe(9);
  });
});
