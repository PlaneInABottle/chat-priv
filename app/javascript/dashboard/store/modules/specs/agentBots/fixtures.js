export const agentBotRecords = [
  {
    account_id: 1,
    id: 11,
    name: 'Agent Bot 11',
    description: 'Agent Bot Description',
    bot_type: 'webhook',
    thumbnail: 'https://example.com/thumbnail.jpg',
    bot_config: {},
    outgoing_url: 'https://example.com/outgoing',
    access_token: 'fake-agent-bot-token',
    system_bot: false,
  },

  {
    account_id: 1,
    id: 12,
    name: 'Agent Bot 12',
    description: 'Agent Bot Description 12',
    bot_type: 'webhook',
    thumbnail: 'https://example.com/thumbnail.jpg',
    bot_config: {},
    outgoing_url: 'https://example.com/outgoing',
    access_token: 'fake-agent-bot-token',
    system_bot: false,
  },
  {
    account_id: 1,
    id: 13,
    name: 'AI Agent Bot',
    description: 'AI Agent Bot Description',
    bot_type: 'ai',
    thumbnail: 'https://example.com/thumbnail.jpg',
    bot_config: {},
    outgoing_url: '',
    access_token: 'fake-agent-bot-token',
    system_bot: false,
  },
];

export const agentBotData = {
  name: 'Test Bot',
  description: 'Test Description',
  outgoing_url: 'https://test.com',
  bot_type: 'webhook',
  avatar: new File([''], 'filename'),
};
