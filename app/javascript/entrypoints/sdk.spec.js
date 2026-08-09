const mocks = vi.hoisted(() => ({
  createFrame: vi.fn(),
  sendMessage: vi.fn(),
  toggleBubble: vi.fn(),
  popoutChatWindow: vi.fn(),
}));

vi.mock('../sdk/IFrameHelper', () => ({
  IFrameHelper: {
    createFrame: mocks.createFrame,
    sendMessage: mocks.sendMessage,
    getAppFrame: vi.fn(),
    events: {
      toggleBubble: mocks.toggleBubble,
      popoutChatWindow: mocks.popoutChatWindow,
    },
  },
}));

import './sdk';

describe('SDK entrypoint compatibility aliases', () => {
  beforeEach(() => {
    delete window.$kozmopath;
    delete window.$chatwoot;
    delete window.kozmopathSettings;
    delete window.chatwootSettings;
    mocks.createFrame.mockClear();
  });

  it('publishes one SDK singleton under both global names', () => {
    expect(window.kozmopathSDK).toBe(window.chatwootSDK);
    expect(window.kozmopathSDK.run).toEqual(expect.any(Function));
  });

  it('merges upstream settings before branded settings and aliases the result', () => {
    window.chatwootSettings = {
      locale: 'en',
      position: 'left',
      launcherTitle: 'Chatwoot',
    };
    window.kozmopathSettings = {
      locale: 'tr',
      launcherTitle: 'Kozmopath',
    };

    window.kozmopathSDK.run({
      baseUrl: 'https://widget.example.test',
      websiteToken: 'website-token',
    });

    expect(window.kozmopathSettings).toEqual({
      locale: 'tr',
      position: 'left',
      launcherTitle: 'Kozmopath',
    });
    expect(window.chatwootSettings).toBe(window.kozmopathSettings);
    expect(window.$chatwoot).toBe(window.$kozmopath);
    expect(window.$kozmopath.locale).toBe('tr');
    expect(window.$kozmopath.position).toBe('left');
    expect(mocks.createFrame).toHaveBeenCalledTimes(1);
  });

  it('reuses an initialized widget when run is called again', () => {
    window.kozmopathSDK.run({
      baseUrl: 'https://widget.example.test',
      websiteToken: 'website-token',
    });
    const existingWidget = window.$kozmopath;

    window.kozmopathSDK.run({
      baseUrl: 'https://other.example.test',
      websiteToken: 'other-token',
    });

    expect(window.$kozmopath).toBe(existingWidget);
    expect(window.$chatwoot).toBe(existingWidget);
    expect(mocks.createFrame).toHaveBeenCalledTimes(1);
  });

  it('aliases an existing upstream singleton without creating another frame', () => {
    const existingWidget = { toggle: vi.fn() };
    window.$chatwoot = existingWidget;

    window.kozmopathSDK.run({
      baseUrl: 'https://widget.example.test',
      websiteToken: 'website-token',
    });

    expect(window.$kozmopath).toBe(existingWidget);
    expect(window.$chatwoot).toBe(existingWidget);
    expect(mocks.createFrame).not.toHaveBeenCalled();
  });
});
