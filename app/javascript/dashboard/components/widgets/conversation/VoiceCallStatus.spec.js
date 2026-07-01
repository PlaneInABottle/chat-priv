import { mount } from '@vue/test-utils';

import VoiceCallStatus from './VoiceCallStatus.vue';

const mountComponent = props =>
  mount(VoiceCallStatus, {
    props,
    global: {
      mocks: {
        $t: key => key,
      },
      stubs: {
        Icon: true,
      },
    },
  });

describe('VoiceCallStatus.vue', () => {
  it('does not use the agent-name declined label without an agent name', () => {
    const wrapper = mountComponent({
      status: 'failed',
      direction: 'inbound',
      endReason: 'agent_rejected_from_popup',
    });

    expect(wrapper.text()).toContain('CONVERSATION.VOICE_CALL.MISSED_CALL');
    expect(wrapper.text()).not.toContain(
      'CONVERSATION.VOICE_CALL.MISSED_CALL_DECLINED_BY'
    );
  });
});
