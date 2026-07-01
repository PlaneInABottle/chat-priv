<script setup>
import { cloneVNode, computed, h, isVNode, useAttrs } from 'vue';

const props = defineProps({
  icon: { type: [String, Object, Function], required: true },
  size: { type: [String, Number], default: '' },
});

defineOptions({
  inheritAttrs: false,
});

const attrs = useAttrs();

const LEGACY_ICON_MAP = {
  add: 'i-lucide-plus',
  alert: 'i-lucide-bell',
  'arrow-clockwise': 'i-lucide-rotate-cw',
  'arrow-redo': 'i-lucide-redo-2',
  'arrow-reply': 'i-lucide-undo-2',
  'arrow-right': 'i-lucide-arrow-right',
  'book-clock': 'i-lucide-clock-3',
  'book-copy': 'i-lucide-book-copy',
  'brand-facebook': 'i-ri-facebook-fill',
  'brand-github': 'i-ri-github-fill',
  'brand-instagram': 'i-ri-instagram-line',
  'brand-line': 'i-ri-line-fill',
  'brand-linkedin': 'i-ri-linkedin-box-fill',
  'brand-sms': 'i-lucide-message-square',
  'brand-telegram': 'i-ri-telegram-fill',
  'brand-tiktok': 'i-ri-tiktok-fill',
  'brand-twitter': 'i-ri-twitter-x-fill',
  'brand-whatsapp': 'i-ri-whatsapp-line',
  checkmark: 'i-lucide-check',
  'checkmark-circle': 'i-lucide-circle-check',
  'chevron-down': 'i-lucide-chevron-down',
  'chevron-left': 'i-lucide-chevron-left',
  'chevron-right': 'i-lucide-chevron-right',
  'cloud-backup': 'i-lucide-cloud-upload',
  copy: 'i-lucide-copy',
  delete: 'i-lucide-trash',
  dismiss: 'i-lucide-x',
  'dismiss-circle': 'i-lucide-circle-x',
  document: 'i-lucide-file',
  emoji: 'i-lucide-smile',
  'eye-hide': 'i-lucide-eye-off',
  'eye-show': 'i-lucide-eye',
  'file-upload': 'i-lucide-upload',
  globe: 'i-lucide-globe',
  'globe-line': 'i-lucide-globe',
  'heart-handshake': 'i-lucide-handshake',
  headphones: 'i-lucide-headphones',
  'headphones-sound-wave': 'i-lucide-headphones',
  image: 'i-lucide-image',
  info: 'i-lucide-info',
  information: 'i-lucide-info',
  linear: 'i-lucide-list-todo',
  link: 'i-lucide-link',
  location: 'i-lucide-map-pin',
  lock: 'i-lucide-lock',
  'lock-closed': 'i-lucide-lock-keyhole',
  mail: 'i-lucide-mail',
  'mail-inbox': 'i-lucide-inbox',
  'mail-unread': 'i-lucide-mail-open',
  open: 'i-lucide-external-link',
  people: 'i-lucide-users',
  'people-team-add': 'i-lucide-users-round',
  person: 'i-lucide-user',
  'person-add': 'i-lucide-user-plus',
  search: 'i-lucide-search',
  'search-check': 'i-lucide-search-check',
  send: 'i-lucide-send',
  'sign-out': 'i-lucide-log-out',
  snooze: 'i-lucide-clock',
  subtract: 'i-lucide-minus',
  tag: 'i-lucide-tag',
  video: 'i-lucide-video',
  'video-add': 'i-lucide-video',
  wand: 'i-lucide-wand-sparkles',
  warning: 'i-lucide-triangle-alert',
  wifi: 'i-lucide-wifi',
  'wifi-off': 'i-lucide-wifi-off',
};

const normalizedIcon = computed(() => {
  if (typeof props.icon !== 'string') return props.icon;
  if (props.icon.startsWith('i-')) return props.icon;
  return LEGACY_ICON_MAP[props.icon] || `i-lucide-${props.icon}`;
});

const sizeClass = computed(() => {
  if (typeof props.size === 'string' && props.size.startsWith('size-')) {
    return props.size;
  }
  return '';
});

const sizeStyle = computed(() => {
  if (!props.size || sizeClass.value) return undefined;
  const value =
    typeof props.size === 'number' || /^\d+$/.test(props.size)
      ? `${props.size}px`
      : props.size;
  return {
    width: value,
    height: value,
    fontSize: value,
  };
});

const renderIcon = () => {
  if (!normalizedIcon.value) return null;

  const mergedAttrs = {
    ...attrs,
    class: [normalizedIcon.value, sizeClass.value, attrs.class],
    style: [attrs.style, sizeStyle.value],
  };

  if (
    mergedAttrs['aria-hidden'] === undefined &&
    !mergedAttrs['aria-label'] &&
    !mergedAttrs.role
  ) {
    mergedAttrs['aria-hidden'] = 'true';
  }

  if (
    typeof normalizedIcon.value === 'function' ||
    isVNode(normalizedIcon.value)
  ) {
    return isVNode(normalizedIcon.value)
      ? cloneVNode(normalizedIcon.value, attrs)
      : h(normalizedIcon.value, attrs);
  }
  return h('span', mergedAttrs);
};
</script>

<template>
  <component :is="renderIcon" />
</template>
