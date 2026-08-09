import { parseBoolean } from '@chatwoot/utils';
import { resolveMaximumFileUploadSize } from 'shared/helpers/FileHelper';

const {
  API_CHANNEL_NAME: apiChannelName,
  API_CHANNEL_THUMBNAIL: apiChannelThumbnail,
  AZURE_APP_ID: azureAppId,
  BRAND_URL: brandURL,
  BRAND_NAME: brandName,
  SUPPORT_INBOX_TOKEN: supportInboxToken,
  CREATE_NEW_ACCOUNT_FROM_DASHBOARD: createNewAccountFromDashboard,
  DIRECT_UPLOADS_ENABLED: directUploadsEnabled,
  DISPLAY_MANIFEST: displayManifest,
  MAXIMUM_FILE_UPLOAD_SIZE: maximumFileUploadSize,
  HCAPTCHA_SITE_KEY: hCaptchaSiteKey,
  INSTALLATION_NAME: installationName,
  LOGO_THUMBNAIL: logoThumbnail,
  LOGO: logo,
  LOGO_DARK: logoDark,
  PRIVACY_URL: privacyURL,
  IS_ENTERPRISE: isEnterprise,
  TERMS_URL: termsURL,
  WIDGET_BRAND_URL: widgetBrandURL,
  DISABLE_USER_PROFILE_UPDATE: disableUserProfileUpdate,
  DEPLOYMENT_ENV: deploymentEnv,
  ACTIVE_PLATFORM_BANNERS: activePlatformBanners,
} = window.globalConfig || {};

const state = {
  apiChannelName,
  apiChannelThumbnail,
  azureAppId,
  brandURL,
  brandName,
  supportInboxToken,
  deploymentEnv,
  createNewAccountFromDashboard,
  directUploadsEnabled: parseBoolean(directUploadsEnabled),
  disableUserProfileUpdate: parseBoolean(disableUserProfileUpdate),
  displayManifest,
  maximumFileUploadSize: resolveMaximumFileUploadSize(maximumFileUploadSize),
  hCaptchaSiteKey,
  installationName,
  logo,
  logoDark,
  logoThumbnail,
  privacyURL,
  termsURL,
  widgetBrandURL,
  isEnterprise: parseBoolean(isEnterprise),
  activePlatformBanners: activePlatformBanners || [],
};

export const getters = {
  get: $state => $state,
  isCloudDeployment: $state => $state.deploymentEnv === 'cloud',
  isOnChatwootCloud: $state => $state.deploymentEnv === 'cloud',
  isACustomBrandedInstance: $state =>
    Boolean($state.brandName) && $state.installationName !== $state.brandName,
  isDefaultInstallation: $state =>
    Boolean($state.brandName) && $state.installationName === $state.brandName,
};

export const actions = {};

export const mutations = {};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
