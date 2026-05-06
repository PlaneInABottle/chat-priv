import AiAgentAPI from '../../../../api/aiAgent';
import { actions } from '../../aiAgent';

vi.mock('../../../../api/aiAgent', () => ({
  default: {
    create: vi.fn(),
    update: vi.fn(),
    get: vi.fn(),
    show: vi.fn(),
    delete: vi.fn(),
  },
}));

describe('aiAgent actions', () => {
  const commit = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('update', () => {
    it('returns parsed validation errors instead of null', async () => {
      AiAgentAPI.update.mockRejectedValue({
        response: {
          data: {
            errors: {
              inbox_ids: ['already assigned to another agent bot'],
            },
          },
        },
      });

      const result = await actions.update(
        { commit, state: { activeId: 1 } },
        { id: 1, data: { inbox_ids: [2] } }
      );

      expect(result).toEqual({
        error: 'already assigned to another agent bot',
      });
    });
  });
});
