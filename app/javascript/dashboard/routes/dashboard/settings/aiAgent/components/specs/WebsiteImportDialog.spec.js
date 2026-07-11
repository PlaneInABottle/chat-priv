import { flushPromises, mount } from '@vue/test-utils';

import WebsiteImportDialog from '../WebsiteImportDialog.vue';

const mockUseAlert = vi.hoisted(() => vi.fn());
const mockApi = vi.hoisted(() => ({
  get: vi.fn(),
  show: vi.fn(),
  create: vi.fn(),
  applyImport: vi.fn(),
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

    show = mockApi.show;

    create = mockApi.create;

    applyImport = mockApi.applyImport;
  },
}));

const readyImport = {
  id: 7,
  status: 'ready',
  stage: 'complete',
  website_url: 'https://example.com/',
  changed_sections: ['business_context'],
  proposed_sections: { business_context: 'Suggested facts' },
  current_document: { sections: { business_context: 'Saved facts' } },
  current_draft_fingerprint: 'current-fingerprint',
  base_draft_fingerprint: 'base-fingerprint',
  draft_changed: false,
  source_urls: ['https://example.com/about'],
};

const DialogStub = {
  name: 'Dialog',
  template: '<div><slot /><slot name="footer" /></div>',
  methods: {
    open() {},
    close() {},
  },
};

const mountComponent = () =>
  mount(WebsiteImportDialog, {
    props: { aiAgentId: 42, defaultWebsite: 'https://example.com/' },
    global: {
      stubs: {
        Dialog: DialogStub,
        Button: {
          name: 'Button',
          props: ['label', 'disabled'],
          emits: ['click'],
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
        Icon: true,
        Spinner: true,
      },
    },
  });

describe('WebsiteImportDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockApi.get.mockResolvedValue({ data: [readyImport] });
    mockApi.applyImport.mockResolvedValue({ data: {} });
  });

  it('compares suggestions with the saved server document and shows sources', async () => {
    const wrapper = mountComponent();

    await wrapper.vm.open();
    await flushPromises();

    expect(wrapper.text()).toContain('Saved facts');
    expect(wrapper.text()).toContain('Suggested facts');
    expect(wrapper.get('a').attributes('href')).toBe(
      'https://example.com/about'
    );
  });

  it('applies against the import base fingerprint', async () => {
    const wrapper = mountComponent();
    await wrapper.vm.open();
    await flushPromises();

    await wrapper.vm.applyImport();

    expect(mockApi.applyImport).toHaveBeenCalledWith(7, {
      section_keys: ['business_context'],
      expected_draft_fingerprint: 'base-fingerprint',
    });
    expect(wrapper.emitted('applied')).toHaveLength(1);
  });

  it('shows a customer-safe failure instead of the backend exception', async () => {
    mockApi.get.mockResolvedValue({
      data: [{ ...readyImport, status: 'running', stage: 'crawling' }],
    });
    mockApi.show.mockResolvedValue({
      data: {
        ...readyImport,
        status: 'failed',
        error_code: 'website_unreachable',
        error_message: 'Connection refused by 10.0.0.4',
      },
    });
    const wrapper = mountComponent();

    await wrapper.vm.open();
    await wrapper.vm.pollImport();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'AI_ASSISTANT.WEBSITE_IMPORT.ERROR.UNREACHABLE'
    );
    expect(wrapper.text()).not.toContain('Connection refused');
  });
});
