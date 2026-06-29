import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';

import VoiceCallStatus from 'dashboard/components-next/Conversation/ConversationCard/VoiceCallStatus.vue';

const mountComponent = (props = {}) =>
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
  it('shows "Call ended" for completed status', async () => {
    const wrapper = await mountComponent({
      status: 'completed',
      direction: 'inbound',
    });
    expect(wrapper.text()).toContain('CONVERSATION.VOICE_CALL.CALL_ENDED');
  });

  it('shows "Missed call" for no-answer inbound', async () => {
    const wrapper = await mountComponent({
      status: 'no-answer',
      direction: 'inbound',
    });
    expect(wrapper.text()).toContain('CONVERSATION.VOICE_CALL.MISSED_CALL');
  });

  it('shows declined label when endReason is agent_rejected', async () => {
    const wrapper = await mountComponent({
      status: 'failed',
      direction: 'inbound',
      endReason: 'agent_rejected',
    });
    expect(wrapper.text()).toContain(
      'CONVERSATION.VOICE_CALL.MISSED_CALL_DECLINED_BY'
    );
  });

  it('shows busy label for busy status', async () => {
    const wrapper = await mountComponent({
      status: 'busy',
      direction: 'outbound',
    });
    expect(wrapper.text()).toContain('CONVERSATION.VOICE_CALL.BUSY');
  });

  it('shows canceled label for canceled status', async () => {
    const wrapper = await mountComponent({
      status: 'canceled',
      direction: 'outbound',
    });
    expect(wrapper.text()).toContain('CONVERSATION.VOICE_CALL.CANCELED');
  });

  it('uses amber color for declined-by-agent calls', async () => {
    const wrapper = await mountComponent({
      status: 'failed',
      direction: 'inbound',
      endReason: 'agent_rejected',
    });
    const coloredElements = wrapper.findAll('.text-n-amber-10');
    expect(coloredElements.length).toBeGreaterThan(0);
  });

  it('uses ruby color for missed calls (no endReason)', async () => {
    const wrapper = await mountComponent({
      status: 'no-answer',
      direction: 'inbound',
    });
    const coloredElements = wrapper.findAll('.text-n-ruby-9');
    expect(coloredElements.length).toBeGreaterThan(0);
  });
});
