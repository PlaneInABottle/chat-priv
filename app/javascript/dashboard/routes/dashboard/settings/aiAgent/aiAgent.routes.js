import { frontendURL } from '../../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import SettingsWrapper from '../SettingsWrapper.vue';
import { redirectIfFeatureDisabled } from '../featureAccessGuard';

const meta = {
  permissions: ['administrator'],
  featureFlag: FEATURE_FLAGS.AI_AGENT,
};
const detailMeta = { ...meta, wideLayout: true };

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/ai-assistants'),
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
          path: 'usage',
          name: 'ai_agent_usage',
          component: () => import('./AiAgentUsage.vue'),
          meta,
        },
        {
          path: 'privacy',
          name: 'ai_agent_data_privacy',
          component: () => import('./AiAgentDataPrivacy.vue'),
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
          redirect: to => ({
            name: 'ai_agent_instructions',
            params: { ...to.params },
          }),
        },
        {
          path: ':id/setup',
          redirect: to => ({
            name: 'ai_agent_detail',
            params: { ...to.params },
          }),
        },
        {
          path: ':id/instructions',
          name: 'ai_agent_instructions',
          component: () => import('./AiAgentDetail.vue'),
          meta: detailMeta,
        },
        {
          path: ':id/connections',
          name: 'ai_agent_detail',
          component: () => import('./AiAgentDetail.vue'),
          meta: detailMeta,
        },
        {
          path: ':id/test',
          name: 'ai_agent_test',
          component: () => import('./AiAgentDetail.vue'),
          meta: detailMeta,
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/ai-agents'),
      redirect: to => ({ name: 'ai_agents', params: to.params }),
    },
  ],
};
