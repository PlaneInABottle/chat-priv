import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/ai-agents'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'ai_agents',
          component: () => import('./AiAgentList.vue'),
          meta: { permissions: ['administrator'] },
        },
        {
          path: 'new',
          name: 'ai_agent_new',
          component: () => import('./AiAgentNew.vue'),
          meta: { permissions: ['administrator'] },
        },
        {
          path: ':id',
          name: 'ai_agent_detail',
          component: () => import('./AiAgentDetail.vue'),
          meta: { permissions: ['administrator'] },
        },
      ],
    },
  ],
};
