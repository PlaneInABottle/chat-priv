import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';

import MessageList from '../MessageList.vue';
import VoiceAPI from 'dashboard/api/voice';

vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: () => ref({ id: 7, messages: [] }),
}));

vi.mock('dashboard/api/voice.js', () => ({
  default: {
    getCall: vi.fn(),
  },
}));

vi.mock('dashboard/api/inbox/message.js', () => ({
  default: {
    getPreviousMessages: vi.fn(),
  },
}));

const mountComponent = message =>
  mount(MessageList, {
    props: {
      currentUserId: 1,
      messages: [message],
    },
    global: {
      stubs: {
        Message: {
          props: ['id'],
          template: '<li :data-testid="`message-` + id">message {{ id }}</li>',
        },
        VoiceTranscriptSegment: {
          props: ['segment'],
          template:
            '<li :data-testid="`segment-` + segment.id">segment {{ segment.id }}</li>',
        },
        VoiceToolEventSegment: true,
      },
    },
  });

const voiceCallMessage = status => ({
  id: 82,
  content_type: 'voice_call',
  message_type: 0,
  status: 'sent',
  created_at: 1782769399,
  call: {
    id: 25,
    status,
  },
});

const mockCallDetails = status => {
  VoiceAPI.getCall.mockResolvedValueOnce({
    data: {
      id: 25,
      status,
      transcript_segments: [
        {
          id: 101,
          role: 'caller',
          text: 'Hello',
          created_at: '2026-06-29T21:43:30Z',
        },
      ],
      tool_event_summaries: [],
    },
  });
};

describe('MessageList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('places completed call transcript rows before the final call bubble', async () => {
    mockCallDetails('completed');
    const wrapper = mountComponent(voiceCallMessage('completed'));
    await flushPromises();

    const items = wrapper
      .findAll('[data-testid]')
      .map(item => item.attributes('data-testid'));

    expect(items).toEqual(['segment-101', 'message-82']);
  });

  it('keeps live call controls before transcript rows', async () => {
    mockCallDetails('in-progress');
    const wrapper = mountComponent(voiceCallMessage('in-progress'));
    await flushPromises();

    const items = wrapper
      .findAll('[data-testid]')
      .map(item => item.attributes('data-testid'));

    expect(items).toEqual(['message-82', 'segment-101']);
  });
});
