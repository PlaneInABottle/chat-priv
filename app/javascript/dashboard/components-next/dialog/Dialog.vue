<script setup>
import { ref, computed, nextTick, useId, useSlots } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'edit',
    validator: value => ['alert', 'edit'].includes(value),
  },
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  cancelButtonLabel: {
    type: String,
    default: '',
  },
  confirmButtonLabel: {
    type: String,
    default: '',
  },
  disableConfirmButton: {
    type: Boolean,
    default: false,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  showCancelButton: {
    type: Boolean,
    default: true,
  },
  showConfirmButton: {
    type: Boolean,
    default: true,
  },
  overflowYAuto: {
    type: Boolean,
    default: false,
  },
  width: {
    type: String,
    default: 'lg',
    validator: value => ['3xl', '2xl', 'xl', 'lg', 'md', 'sm'].includes(value),
  },
  position: {
    type: String,
    default: 'center',
    validator: value => ['center', 'top'].includes(value),
  },
});

const emit = defineEmits(['confirm', 'close']);

const { t } = useI18n();

const dialogRef = ref(null);
const dialogContentRef = ref(null);
const isOpen = ref(false);
const titleId = useId();
const descriptionId = useId();
const previouslyFocusedElement = ref(null);
const slots = useSlots();

const maxWidthClass = computed(() => {
  const classesMap = {
    '3xl': 'max-w-3xl',
    '2xl': 'max-w-2xl',
    xl: 'max-w-xl',
    lg: 'max-w-lg',
    md: 'max-w-md',
    sm: 'max-w-sm',
  };

  return classesMap[props.width] ?? 'max-w-md';
});

const positionClass = computed(() =>
  props.position === 'top' ? 'dialog-position-top' : ''
);

const hasDescription = computed(
  () => !!props.description || !!slots.description
);

const focusableSelector = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(',');

const getFocusableElements = () => {
  const content = dialogContentRef.value;
  if (!content) return [];

  return Array.from(content.querySelectorAll(focusableSelector)).filter(
    element =>
      !element.hasAttribute('disabled') &&
      element.getAttribute('aria-hidden') !== 'true' &&
      element.offsetParent !== null
  );
};

const focusFirstElement = () => {
  nextTick(() => {
    const [first] = getFocusableElements();
    (first || dialogRef.value)?.focus();
  });
};

const trapFocus = e => {
  if (e.key !== 'Tab') return;
  const focusable = getFocusableElements();
  if (focusable.length === 0) return;
  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (e.shiftKey && document.activeElement === first) {
    e.preventDefault();
    last.focus();
  } else if (!e.shiftKey && document.activeElement === last) {
    e.preventDefault();
    first.focus();
  }
};

const open = async () => {
  previouslyFocusedElement.value = document.activeElement;
  isOpen.value = true;
  await nextTick();
  dialogRef.value?.showModal();
  focusFirstElement();
};

const close = () => {
  emit('close');
  dialogRef.value?.close();
  isOpen.value = false;
  previouslyFocusedElement.value?.focus?.();
};

// Only close if the close event originated from this dialog,
// not from a child dialog (e.g. ProseMirror prompt) bubbling up.
const handleDialogClose = e => e.target === dialogRef.value && close();

// Only close on click-outside if this dialog is the topmost one.
// If another dialog (e.g. ProseMirror prompt) is open on top, ignore.
const handleClickOutside = () => {
  const dialogs = document.querySelectorAll('dialog[open]');
  if (dialogs[dialogs.length - 1] === dialogRef.value) close();
};

const confirm = () => {
  emit('confirm');
};

defineExpose({ open, close });
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      ref="dialogRef"
      class="w-full transition-all duration-300 ease-in-out shadow-xl rounded-xl"
      :class="[
        maxWidthClass,
        positionClass,
        overflowYAuto ? 'overflow-y-auto' : 'overflow-visible',
      ]"
      :aria-labelledby="title ? titleId : undefined"
      :aria-describedby="hasDescription ? descriptionId : undefined"
      @close.prevent="handleDialogClose"
      @keydown="trapFocus"
    >
      <OnClickOutside @trigger="handleClickOutside">
        <form
          ref="dialogContentRef"
          class="flex flex-col w-full h-auto gap-6 p-6 overflow-visible text-start align-middle transition-all duration-300 ease-in-out transform bg-n-alpha-3 backdrop-blur-[100px] shadow-xl rounded-xl"
          @submit.prevent="confirm"
          @click.stop
        >
          <div
            v-if="title || description || $slots.description"
            class="flex flex-col gap-2"
          >
            <h3
              v-if="title"
              :id="titleId"
              class="text-base font-medium leading-6 text-n-slate-12"
            >
              {{ title }}
            </h3>
            <p
              v-if="description"
              :id="descriptionId"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ description }}
            </p>
            <div
              v-if="!description && $slots.description"
              :id="descriptionId"
              class="text-sm text-n-slate-11"
            >
              <slot name="description" />
            </div>
          </div>
          <slot v-if="isOpen" />
          <!-- Dialog content will be injected here -->
          <slot name="footer">
            <div
              v-if="showCancelButton || showConfirmButton"
              class="flex items-center justify-between w-full gap-3"
            >
              <Button
                v-if="showCancelButton"
                variant="faded"
                color="slate"
                :label="cancelButtonLabel || t('DIALOG.BUTTONS.CANCEL')"
                class="w-full"
                type="button"
                @click="close"
              />
              <Button
                v-if="showConfirmButton"
                :color="type === 'edit' ? 'blue' : 'ruby'"
                :label="confirmButtonLabel || t('DIALOG.BUTTONS.CONFIRM')"
                class="w-full"
                :is-loading="isLoading"
                :disabled="disableConfirmButton || isLoading"
                type="submit"
              />
            </div>
          </slot>
        </form>
      </OnClickOutside>
    </dialog>
  </TeleportWithDirection>
</template>

<style scoped>
dialog::backdrop {
  @apply bg-n-alpha-black1 backdrop-blur-[4px];
}

.dialog-position-top {
  margin-top: clamp(2rem, 5vh, 5rem);
  margin-bottom: auto;
}
</style>
