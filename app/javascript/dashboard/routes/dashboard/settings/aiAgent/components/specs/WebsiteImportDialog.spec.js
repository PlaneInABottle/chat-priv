import { flushPromises, mount } from '@vue/test-utils';

import WebsiteImportDialog from '../WebsiteImportDialog.vue';

const mockUseAlert = vi.hoisted(() => vi.fn());
const mockApi = vi.hoisted(() => ({
  get: vi.fn(),
  show: vi.fn(),
  create: vi.fn(),
  applyImport: vi.fn(),
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

    show = mockApi.show;

    create = mockApi.create;

    applyImport = mockApi.applyImport;

    dismiss = mockApi.dismiss;
  },
}));

const readyImport = {
  id: 7,
  status: 'ready',
  stage: 'complete',
  website_url: 'https://example.com/',
  proposed_sections: { business_context: 'Suggested facts' },
  base_document: { sections: { business_context: 'Saved facts' } },
  has_review_context: true,
  knowledge_available: true,
  knowledge_character_count: 2400,
  source_count: 1,
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

const currentDocument = {
  version: 4,
  locale: 'en',
  profile: {},
  sections: { business_context: 'Saved facts' },
};

const mountComponent = (document = currentDocument) =>
  mount(WebsiteImportDialog, {
    props: {
      aiAgentId: 42,
      defaultWebsite: 'https://example.com/',
      currentDocument: document,
      expectedDraftFingerprint: 'loaded-fingerprint',
    },
    global: {
      directives: {
        dompurifyHtml: (element, binding) => {
          element.innerHTML = binding.value;
        },
      },
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
        ImprovementCreditsSummary: {
          name: 'ImprovementCreditsSummary',
          template: '<div />',
          emits: ['loaded'],
          methods: { refresh() {} },
        },
      },
    },
  });

describe('WebsiteImportDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockApi.get.mockResolvedValue({ data: [readyImport] });
    mockApi.applyImport.mockResolvedValue({ data: {} });
    mockApi.dismiss.mockResolvedValue({ data: {} });
  });

  it('compares suggestions with the current local document and shows sources', async () => {
    const wrapper = mountComponent();

    await wrapper.vm.open();
    await flushPromises();

    expect(wrapper.text()).toContain('Saved facts');
    expect(wrapper.text()).toContain('Suggested facts');
    expect(wrapper.get('a').attributes('href')).toBe(
      'https://example.com/about'
    );
  });

  it('renders point-by-point suggestions as a readable list', async () => {
    mockApi.get.mockResolvedValue({
      data: [
        {
          ...readyImport,
          proposed_sections: {
            business_context: '- Verified fact one\n- Verified fact two',
          },
        },
      ],
    });
    const wrapper = mountComponent();

    await wrapper.vm.open();
    await flushPromises();

    expect(wrapper.findAll('.prose li').map(item => item.text())).toEqual([
      'Verified fact one',
      'Verified fact two',
    ]);
  });

  it('saves local edits, selected suggestions, and website knowledge together', async () => {
    const wrapper = mountComponent();
    await wrapper.vm.open();
    await flushPromises();

    await wrapper.vm.applyImport();

    expect(mockApi.applyImport).toHaveBeenCalledWith(7, {
      section_keys: ['business_context'],
      current_document: currentDocument,
      attach_knowledge: true,
      expected_draft_fingerprint: 'loaded-fingerprint',
    });
    expect(wrapper.emitted('applied')).toHaveLength(1);
  });

  it('keeps a section edited after analysis unless the customer chooses the suggestion', async () => {
    const editedDocument = {
      ...currentDocument,
      sections: { business_context: 'My unsaved edit' },
    };
    const wrapper = mountComponent(editedDocument);
    await wrapper.vm.open();
    await flushPromises();

    expect(wrapper.vm.sectionChoices.business_context).toBe('current');
    expect(wrapper.text()).toContain('My unsaved edit');
    expect(wrapper.text()).toContain(
      'AI_ASSISTANT.WEBSITE_IMPORT.EDITED_SINCE_ANALYSIS'
    );
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

  it('blocks new analysis when improvement credits are exhausted', async () => {
    mockApi.get.mockResolvedValue({ data: [] });
    const wrapper = mountComponent();
    await wrapper.vm.open();
    wrapper
      .findComponent({ name: 'ImprovementCreditsSummary' })
      .vm.$emit('loaded', { status: 'exhausted' });
    await wrapper.vm.$nextTick();

    wrapper.vm.websiteUrl = 'https://example.com/';
    await wrapper.vm.startImport();

    expect(mockApi.create).not.toHaveBeenCalled();
    expect(
      wrapper.find('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
  });

  it('keeps the website field focus ring visible and aligned with its action', async () => {
    mockApi.get.mockResolvedValue({ data: [] });
    const wrapper = mountComponent();
    await wrapper.vm.open();
    await flushPromises();

    const input = wrapper.get('input[name="website_url"]');
    const label = input.element.closest('label');
    const scrollBody = input.element.closest('.overflow-y-auto');

    expect(input.classes()).toContain('!mb-0');
    expect(input.classes()).toContain('focus-visible:ring-inset');
    expect(label.classList).toContain('flex-col');
    expect(scrollBody.classList).toContain('px-1');
    expect(scrollBody.classList).not.toContain('min-h-72');
  });

  it('discards an unusable ready preview before starting over', async () => {
    mockApi.get.mockResolvedValue({
      data: [{ ...readyImport, proposed_sections: {} }],
    });
    const wrapper = mountComponent();
    await wrapper.vm.open();
    await flushPromises();

    await wrapper.vm.restartImport();

    expect(mockApi.dismiss).toHaveBeenCalledWith(7);
    expect(wrapper.vm.websiteImport).toBeNull();
  });

  it('requires a new analysis when the saved draft changed during review', async () => {
    mockApi.applyImport.mockRejectedValue({
      response: { data: { code: 'draft_changed' } },
    });
    const wrapper = mountComponent();
    await wrapper.vm.open();
    await flushPromises();

    await wrapper.vm.applyImport();

    expect(wrapper.vm.canApply).toBe(false);
    expect(wrapper.vm.canRestart).toBe(true);
    expect(wrapper.text()).toContain(
      'AI_ASSISTANT.WEBSITE_IMPORT.ERROR.DRAFT_CHANGED'
    );
  });

  it('explains when the assistant already uses the knowledge source limit', async () => {
    mockApi.applyImport.mockRejectedValue({
      response: { data: { code: 'knowledge_source_limit' } },
    });
    const wrapper = mountComponent();
    await wrapper.vm.open();
    await flushPromises();

    await wrapper.vm.applyImport();

    expect(mockUseAlert).toHaveBeenCalledWith(
      'AI_ASSISTANT.WEBSITE_IMPORT.ERROR.KNOWLEDGE_SOURCE_LIMIT'
    );
  });
});
