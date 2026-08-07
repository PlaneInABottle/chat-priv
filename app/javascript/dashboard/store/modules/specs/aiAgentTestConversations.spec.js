import AiAgentTestConversationsAPI from '../../../api/aiAgentTestConversations';
import { actions, mutations } from '../aiAgentTestConversations';

vi.mock('../../../api/aiAgentTestConversations', () => ({
  default: vi.fn(),
}));

describe('aiAgentTestConversations store', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('actions', () => {
    it('resets conversation state', () => {
      const commit = vi.fn();

      actions.reset({ commit });

      expect(commit).toHaveBeenCalledWith('RESET_CONVERSATIONS_STATE');
    });

    it('skips stale overlapping list responses for a previous aiAgentId', async () => {
      let activeAiAgentId = 1;
      const commit = vi.fn();
      const pendingResponses = {};

      AiAgentTestConversationsAPI.mockImplementation(aiAgentId => ({
        get: vi.fn(
          () =>
            new Promise(resolve => {
              pendingResponses[aiAgentId] = resolve;
            })
        ),
      }));

      const firstLoad = actions.get(
        {
          commit,
          rootState: {
            aiAgent: {
              get activeId() {
                return activeAiAgentId;
              },
            },
          },
        },
        { aiAgentId: 1 }
      );

      activeAiAgentId = 2;

      const secondLoad = actions.get(
        {
          commit,
          rootState: {
            aiAgent: {
              get activeId() {
                return activeAiAgentId;
              },
            },
          },
        },
        { aiAgentId: 2 }
      );

      pendingResponses[2]({ data: [{ id: 22, title: 'Agent B' }] });
      await secondLoad;

      pendingResponses[1]({ data: [{ id: 11, title: 'Agent A' }] });
      await firstLoad;

      expect(commit).toHaveBeenCalledWith('SET_CONVERSATIONS', [
        { id: 22, title: 'Agent B' },
      ]);
      expect(commit).not.toHaveBeenCalledWith('SET_CONVERSATIONS', [
        { id: 11, title: 'Agent A' },
      ]);
    });

    it('handles sendMessage failures without throwing and removes optimistic message', async () => {
      const commit = vi.fn();
      const error = {
        response: { data: { message: 'AI response failed' } },
      };
      const sendMessage = vi.fn().mockRejectedValue(error);

      AiAgentTestConversationsAPI.mockImplementation(() => ({
        sendMessage,
      }));

      const result = await actions.sendMessage(
        {
          commit,
          rootState: {
            aiAgent: {
              activeId: 7,
            },
          },
        },
        {
          id: 99,
          content: 'Hello there',
        }
      );

      const optimisticCommit = commit.mock.calls.find(
        ([type]) => type === 'ADD_MESSAGE'
      );

      expect(result).toEqual({ error: 'AI response failed' });
      expect(sendMessage).toHaveBeenCalledWith(99, 'Hello there', undefined, {
        replyToMessageId: undefined,
        selectedValue: undefined,
      });
      expect(commit).toHaveBeenCalledWith('SET_UI_FLAG', {
        isSending: true,
        sendingConversationId: 99,
      });
      expect(optimisticCommit[1]).toEqual({
        id: 99,
        message: expect.objectContaining({
          id: expect.stringMatching(/^temp-/),
          role: 'user',
          content: 'Hello there',
        }),
      });
      expect(commit).toHaveBeenCalledWith('REMOVE_MESSAGE', {
        id: 99,
        messageId: optimisticCommit[1].message.id,
      });
      expect(commit).toHaveBeenLastCalledWith('SET_UI_FLAG', {
        isSending: false,
        sendingConversationId: null,
      });
    });

    it('clears the sending conversation id after a successful send', async () => {
      const commit = vi.fn();
      const response = {
        data: {
          messages: [
            { id: 'a-1', role: 'assistant', content: 'Happy to help!' },
          ],
          title: 'Conversation',
        },
      };
      const sendMessage = vi.fn().mockResolvedValue(response);
      AiAgentTestConversationsAPI.mockImplementation(() => ({ sendMessage }));

      await actions.sendMessage(
        { commit, rootState: { aiAgent: { activeId: 7 } } },
        { id: 42, content: 'Hello' }
      );

      expect(commit).toHaveBeenCalledWith('SET_UI_FLAG', {
        isSending: true,
        sendingConversationId: 42,
      });

      const optimisticCommit = commit.mock.calls.find(
        ([type]) => type === 'ADD_MESSAGE'
      );
      expect(optimisticCommit[1]).toEqual({
        id: 42,
        message: expect.objectContaining({
          id: expect.stringMatching(/^temp-/),
          role: 'user',
          content: 'Hello',
        }),
      });
      expect(commit).toHaveBeenCalledWith('UPDATE_MESSAGES', {
        id: 42,
        messages: response.data.messages,
        title: response.data.title,
      });
      expect(commit).not.toHaveBeenCalledWith(
        'REMOVE_MESSAGE',
        expect.anything()
      );
      expect(commit).toHaveBeenLastCalledWith('SET_UI_FLAG', {
        isSending: false,
        sendingConversationId: null,
      });
    });

    it('forwards a selected option with its prompt identifier', async () => {
      const commit = vi.fn();
      const sendMessage = vi.fn().mockResolvedValue({
        data: { messages: [], title: 'Options' },
      });
      AiAgentTestConversationsAPI.mockImplementation(() => ({ sendMessage }));

      await actions.sendMessage(
        { commit, rootState: { aiAgent: { activeId: 7 } } },
        {
          id: 99,
          content: 'Support',
          replyToMessageId: 'options-1',
          selectedValue: 'support',
        }
      );

      expect(sendMessage).toHaveBeenCalledWith(99, 'Support', undefined, {
        replyToMessageId: 'options-1',
        selectedValue: 'support',
      });
    });
  });

  describe('mutations', () => {
    it('clears stale activeId when loaded list does not contain it', () => {
      const state = {
        records: { 1: { id: 1, title: 'Old' } },
        sortOrder: [1],
        activeId: 1,
      };

      mutations.SET_CONVERSATIONS(state, [{ id: 2, title: 'New' }]);

      expect(state.records).toEqual({ 2: { id: 2, title: 'New' } });
      expect(state.sortOrder).toEqual([2]);
      expect(state.activeId).toBeNull();
    });

    it('resets all conversation state', () => {
      const state = {
        records: { 1: { id: 1, title: 'Old' } },
        sortOrder: [1],
        activeId: 1,
      };

      mutations.RESET_CONVERSATIONS_STATE(state);

      expect(state.records).toEqual({});
      expect(state.sortOrder).toEqual([]);
      expect(state.activeId).toBeNull();
    });

    it('removes a message and restores conversation previews', () => {
      const state = {
        records: {
          1: {
            id: 1,
            messages: [
              {
                id: 'm1',
                content: 'First',
                created_at: '2024-01-01T00:00:00Z',
              },
              {
                id: 'temp-1',
                content: 'Optimistic',
                created_at: '2024-01-02T00:00:00Z',
              },
            ],
            messages_count: 2,
            last_message_at: '2024-01-02T00:00:00Z',
            last_message_preview: 'Optimistic',
          },
        },
        sortOrder: [1],
        activeId: 1,
      };

      mutations.REMOVE_MESSAGE(state, { id: 1, messageId: 'temp-1' });

      expect(state.records[1].messages).toEqual([
        { id: 'm1', content: 'First', created_at: '2024-01-01T00:00:00Z' },
      ]);
      expect(state.records[1].messages_count).toBe(1);
      expect(state.records[1].last_message_at).toBe('2024-01-01T00:00:00Z');
      expect(state.records[1].last_message_preview).toBe('First');
    });

    it('derives preview text from handoff terminal messages', () => {
      const state = {
        records: {
          1: {
            id: 1,
            messages: [],
            messages_count: 0,
            last_message_at: null,
            last_message_preview: null,
          },
        },
        sortOrder: [1],
        activeId: 1,
      };

      mutations.UPDATE_MESSAGES(state, {
        id: 1,
        title: 'Conversation',
        messages: [
          {
            id: 'handoff',
            role: 'assistant',
            terminal_action: 'handoff',
            created_at: '2024-01-03T00:00:00Z',
            tool_result: {
              customer_message:
                'Transferring to another agent for further assistance.',
              labels_ignored: ['missing'],
            },
          },
        ],
      });

      expect(state.records[1].last_message_preview).toBe(
        'Transferring to another agent for further assistance.'
      );
    });
  });
});
