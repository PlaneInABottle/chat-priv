import { frontendURL } from '../../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import SettingsWrapper from '../SettingsWrapper.vue';
import { redirectIfFeatureDisabled } from '../featureAccessGuard';

const meta = {
  permissions: ['administrator'],
  featureFlag: FEATURE_FLAGS.VOICE_AI,
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/voice-ai'),
      component: SettingsWrapper,
      beforeEnter: redirectIfFeatureDisabled,
      children: [
        {
          path: '',
          name: 'voice_ai_settings',
          component: () => import('./VoiceAiSettings.vue'),
          meta,
        },
      ],
    },
  ],
};
