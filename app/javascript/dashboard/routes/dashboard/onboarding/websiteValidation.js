const HOST_LABEL_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i;
const isIpv4Address = labels =>
  labels.length === 4 &&
  labels.every(label => /^\d{1,3}$/.test(label) && Number(label) <= 255);

export const normalizeWebsiteInput = value => {
  const input = value.trim();
  if (!input) return '';

  try {
    const candidate = /^https?:\/\//i.test(input) ? input : `https://${input}`;
    const url = new URL(candidate);
    const labels = url.hostname.split('.');
    const hasValidHost =
      labels.length > 1 &&
      labels.at(-1).length > 1 &&
      labels.every(label => HOST_LABEL_PATTERN.test(label));

    if (
      !['http:', 'https:'].includes(url.protocol) ||
      url.username ||
      url.password ||
      isIpv4Address(labels) ||
      !hasValidHost
    ) {
      return null;
    }

    url.hash = '';
    return url.toString();
  } catch {
    return null;
  }
};
