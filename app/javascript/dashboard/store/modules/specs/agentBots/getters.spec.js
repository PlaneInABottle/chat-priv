import { getters } from '../../agentBots';
import { agentBotRecords } from './fixtures';

describe('#getters', () => {
  it('getBots', () => {
    const state = { records: agentBotRecords };
    expect(getters.getBots(state)).toEqual(
      agentBotRecords.filter(bot => bot.bot_type === 'webhook')
    );
  });

  it('getBot', () => {
    const state = { records: agentBotRecords };
    expect(getters.getBot(state)(11)).toEqual(agentBotRecords[0]);
  });

  it('getUIFlags', () => {
    const state = {
      uiFlags: {
        isFetching: true,
        isCreating: false,
        isUpdating: false,
        isDeleting: false,
      },
    };
    expect(getters.getUIFlags(state)).toEqual({
      isFetching: true,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    });
  });
});
