/**
 * Composable for branding-related utilities
 * Provides methods to customize text with installation-specific branding
 */
import { useMapGetter } from 'dashboard/composables/store.js';

const installationNameFrom = config =>
  config?.INSTALLATION_NAME || config?.installationName;
const upstreamProductName = ['Chat', 'woot'].join('');
const voiceTransportName = ['Live', 'Kit'].join('');

const brandHostFrom = config => {
  const brandURL = config?.BRAND_URL || config?.brandURL;

  try {
    return brandURL ? new URL(brandURL).host : window.location.host;
  } catch {
    return window.location.host;
  }
};

export const replacePublicBranding = (text, config = {}) => {
  if (!text) return text;

  const installationName = installationNameFrom(config);
  if (!installationName) return text;

  const brandHost = brandHostFrom(config);
  const upstreamDomain = upstreamProductName.toLowerCase();

  return text
    .replace(
      new RegExp(
        `(?:app\\.|www\\.)?${upstreamDomain}\\.com|${upstreamDomain}\\.help`,
        'gi'
      ),
      brandHost
    )
    .replace(new RegExp(voiceTransportName, 'gi'), `${installationName} Voice`)
    .replace(new RegExp(upstreamProductName, 'gi'), installationName);
};

export const replaceTranslatedBranding = text =>
  replacePublicBranding(text, window.globalConfig || {});

export function useBranding() {
  const globalConfig = useMapGetter('globalConfig/get');
  /**
   * Replaces public product and voice-provider names with installation branding.
   * @param {string} text - The text to process
   * @returns {string} - Text with public product, domain, and voice-provider branding replaced
   */
  const replaceInstallationName = text => {
    if (!text) return text;

    return replacePublicBranding(text, globalConfig.value);
  };

  return {
    replaceInstallationName,
  };
}
