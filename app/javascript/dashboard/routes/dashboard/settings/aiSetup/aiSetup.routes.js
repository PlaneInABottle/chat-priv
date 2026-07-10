import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';

const meta = {
  permissions: ['administrator'],
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/ai-setup'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'ai_setup',
          component: () => import('./AiSetup.vue'),
          meta,
        },
      ],
    },
  ],
};
