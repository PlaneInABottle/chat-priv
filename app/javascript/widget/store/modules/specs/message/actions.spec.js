import { API } from 'widget/helpers/axios';
import { actions } from '../../message';

const commit = vi.fn();
vi.mock('widget/helpers/axios');

describe('#actions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('#select', () => {
    it('submits one AI option and appends the incoming response message', async () => {
      const responseMessage = {
        id: 42,
        content: 'Support',
        message_type: 0,
      };
      API.post.mockResolvedValue({ data: responseMessage });

      await actions.select(
        {
          commit,
          getters: { getUIFlags: { isUpdating: false } },
        },
        {
          messageId: 10,
          selectedOption: { title: 'Support', value: 'support-id' },
        }
      );

      expect(API.post).toHaveBeenCalledWith(
        expect.stringContaining('/api/v1/widget/messages/10/select'),
        { message: { selected_value: 'support-id' } }
      );
      expect(commit).toHaveBeenCalledWith(
        'conversation/updateMessage',
        {
          id: 10,
          content_attributes: {
            submitted_values: [{ title: 'Support', value: 'support-id' }],
          },
        },
        { root: true }
      );
      expect(commit).toHaveBeenCalledWith(
        'conversation/pushMessageToConversation',
        responseMessage,
        { root: true }
      );
    });
  });

  describe('#update', () => {
    it('sends correct actions', async () => {
      const user = {
        email: 'john@acme.inc',
        messageId: 10,
        submittedValues: {
          email: 'john@acme.inc',
        },
      };
      API.patch.mockResolvedValue({
        data: { contact: { pubsub_token: '8npuMUfDgizrwVoqcK1t7FMY' } },
      });
      await actions.update(
        {
          commit,
          getters: {
            getUIFlags: {
              isUpdating: false,
            },
          },
        },
        user
      );
      expect(commit.mock.calls).toEqual([
        ['toggleUpdateStatus', true],
        [
          'conversation/updateMessage',
          {
            id: 10,
            content_attributes: {
              submitted_email: 'john@acme.inc',
              submitted_values: null,
            },
          },
          { root: true },
        ],
        ['toggleUpdateStatus', false],
      ]);
    });

    it('blocks all new action calls when isUpdating', async () => {
      await actions.update(
        {
          commit,
          getters: {
            getUIFlags: {
              isUpdating: true,
            },
          },
        },
        {}
      );

      expect(commit.mock.calls).toEqual([]);
    });
  });
});
