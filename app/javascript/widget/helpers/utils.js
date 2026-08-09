import { LEGACY_WOOT_PREFIX, WOOT_PREFIX } from './constants';

const MESSAGE_PREFIXES = [WOOT_PREFIX, LEGACY_WOOT_PREFIX];
const messagePrefix = data =>
  MESSAGE_PREFIXES.find(prefix => data.indexOf(prefix) === 0);

export const isEmptyObject = obj => {
  if (!obj) return true;
  return Object.keys(obj).length === 0 && obj.constructor === Object;
};

export const sendMessage = msg => {
  window.parent.postMessage(`${WOOT_PREFIX}${JSON.stringify({ ...msg })}`, '*');
};

export const IFrameHelper = {
  isIFrame: () => window.self !== window.top,
  sendMessage,
  isAValidEvent: e => {
    const isDataAString = typeof e.data === 'string';
    return isDataAString && Boolean(messagePrefix(e.data));
  },
  getMessage: e => JSON.parse(e.data.replace(messagePrefix(e.data), '')),
};
export const RNHelper = {
  isRNWebView: () => window.ReactNativeWebView,
  sendMessage: msg => {
    window.ReactNativeWebView.postMessage(
      `${WOOT_PREFIX}${JSON.stringify({ ...msg })}`
    );
  },
};

export const groupBy = (array, predicate) => {
  return array.reduce((acc, value) => {
    (acc[predicate(value)] ||= []).push(value);
    return acc;
  }, {});
};
