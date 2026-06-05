import 'chart.js';
import { createApp, h } from 'vue';
import VueDOMPurifyHTML from 'vue-dompurify-html';

import DashboardIndex from '../superadmin_pages/views/dashboard/Index.vue';
import AiAgentToolExecutionsIndex from '../superadmin_pages/views/ai_agent_tool_executions/Index.vue';

const ComponentMapping = {
  DashboardIndex: DashboardIndex,
  AiAgentToolExecutionsIndex: AiAgentToolExecutionsIndex,
};

const renderComponent = (componentName, props) => {
  const app = createApp({
    data() {
      return { props: props };
    },
    render() {
      return h(ComponentMapping[componentName], { componentData: this.props });
    },
  });

  app.use(VueDOMPurifyHTML);
  app.mount('#app');
};

document.addEventListener('DOMContentLoaded', () => {
  const element = document.getElementById('app');
  if (element) {
    const componentName = element.dataset.componentName;
    const props = JSON.parse(element.dataset.props);
    renderComponent(componentName, props);
  }
});
