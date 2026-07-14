import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';

import Dialog from './Dialog.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const ButtonStub = {
  props: ['label', 'disabled', 'isLoading'],
  emits: ['click'],
  template: `
    <button
      :disabled="disabled || isLoading"
      @click="$emit('click')"
    >
      {{ label }}
    </button>
  `,
};

const mountDialog = props =>
  mount(Dialog, {
    props: {
      title: 'Delete contact',
      description: 'This action cannot be undone.',
      cancelButtonLabel: 'Cancel',
      confirmButtonLabel: 'Delete',
      ...props,
    },
    attachTo: document.body,
    global: {
      stubs: {
        Button: ButtonStub,
        OnClickOutside: { template: '<div><slot /></div>' },
        TeleportWithDirection: { template: '<div><slot /></div>' },
      },
    },
  });

const mountDialogWithSlots = options =>
  mount(Dialog, {
    attachTo: document.body,
    global: {
      stubs: {
        Button: ButtonStub,
        OnClickOutside: { template: '<div><slot /></div>' },
        TeleportWithDirection: { template: '<div><slot /></div>' },
      },
    },
    ...options,
  });

describe('Dialog.vue', () => {
  it('supports extra-wide review dialogs', async () => {
    const wrapper = mountDialog({ width: '4xl' });

    await wrapper.vm.open();

    expect(wrapper.find('dialog').classes()).toContain('max-w-4xl');
  });

  const originalShowModal = HTMLDialogElement.prototype.showModal;
  const originalClose = HTMLDialogElement.prototype.close;
  const originalOffsetParent = Object.getOwnPropertyDescriptor(
    HTMLElement.prototype,
    'offsetParent'
  );

  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = function showModal() {
      this.open = true;
    };
    HTMLDialogElement.prototype.close = function close() {
      this.open = false;
    };
    Object.defineProperty(HTMLElement.prototype, 'offsetParent', {
      configurable: true,
      get() {
        return document.body;
      },
    });
  });

  afterAll(() => {
    HTMLDialogElement.prototype.showModal = originalShowModal;
    HTMLDialogElement.prototype.close = originalClose;
    if (originalOffsetParent) {
      Object.defineProperty(
        HTMLElement.prototype,
        'offsetParent',
        originalOffsetParent
      );
    }
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('labels the dialog and focuses the first action on open', async () => {
    const wrapper = mountDialog();

    await wrapper.vm.open();
    await nextTick();
    await nextTick();

    const dialog = wrapper.find('dialog');
    const titleId = dialog.attributes('aria-labelledby');
    const descriptionId = dialog.attributes('aria-describedby');

    expect(titleId).toBeTruthy();
    expect(descriptionId).toBeTruthy();
    expect(wrapper.find(`#${titleId}`).text()).toBe('Delete contact');
    expect(wrapper.find(`#${descriptionId}`).text()).toBe(
      'This action cannot be undone.'
    );
    expect(document.activeElement?.textContent.trim()).toBe('Cancel');
  });

  it('traps tab focus and restores previous focus on close', async () => {
    const opener = document.createElement('button');
    opener.textContent = 'Open dialog';
    document.body.appendChild(opener);
    opener.focus();

    const wrapper = mountDialog();
    await wrapper.vm.open();
    await nextTick();
    await nextTick();

    const buttons = wrapper.findAll('button');
    const [cancelButton, confirmButton] = buttons.map(button => button.element);
    const dialog = wrapper.find('dialog').element;

    confirmButton.focus();
    const tabForward = new KeyboardEvent('keydown', {
      key: 'Tab',
      bubbles: true,
      cancelable: true,
    });
    dialog.dispatchEvent(tabForward);

    expect(tabForward.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(cancelButton);

    const tabBackward = new KeyboardEvent('keydown', {
      key: 'Tab',
      shiftKey: true,
      bubbles: true,
      cancelable: true,
    });
    cancelButton.focus();
    dialog.dispatchEvent(tabBackward);

    expect(tabBackward.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(confirmButton);

    wrapper.vm.close();

    expect(document.activeElement).toBe(opener);
  });

  it('links slotted descriptions to aria-describedby', async () => {
    const wrapper = mountDialogWithSlots({
      props: {
        title: 'Archive conversation',
        cancelButtonLabel: 'Cancel',
        confirmButtonLabel: 'Archive',
      },
      slots: {
        description: '<p>Archived conversations can be restored later.</p>',
      },
    });

    await wrapper.vm.open();
    await nextTick();
    await nextTick();

    const descriptionId = wrapper.find('dialog').attributes('aria-describedby');

    expect(descriptionId).toBeTruthy();
    expect(wrapper.find(`#${descriptionId}`).text()).toBe(
      'Archived conversations can be restored later.'
    );
  });
});
