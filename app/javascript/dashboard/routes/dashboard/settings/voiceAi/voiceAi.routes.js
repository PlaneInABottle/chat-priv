import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/voice-ai'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'voice_ai_settings',
          component: () => import('./VoiceAiSettings.vue'),
          meta: { permissions: ['administrator'] },
        },
      ],
    },
  ],
};
