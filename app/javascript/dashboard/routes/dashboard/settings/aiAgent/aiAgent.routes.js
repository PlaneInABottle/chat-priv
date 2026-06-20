import { frontendURL } from '../../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import SettingsWrapper from '../SettingsWrapper.vue';
import { redirectIfFeatureDisabled } from '../featureAccessGuard';

const meta = {
  permissions: ['administrator'],
  featureFlag: FEATURE_FLAGS.AI_AGENT,
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/ai-agents'),
      component: SettingsWrapper,
      beforeEnter: redirectIfFeatureDisabled,
      children: [
        {
          path: '',
          name: 'ai_agents',
          component: () => import('./AiAgentList.vue'),
          meta,
        },
        {
          path: 'new',
          name: 'ai_agent_new',
          component: () => import('./AiAgentNew.vue'),
          meta,
        },
        {
          path: ':id',
          name: 'ai_agent_detail',
          component: () => import('./AiAgentDetail.vue'),
          meta,
        },
      ],
    },
  ],
};
