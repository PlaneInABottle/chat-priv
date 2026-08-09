import { IFrameHelper } from '../IFrameHelper';

const message = (prefix, event = 'message-received') =>
  `${prefix}${JSON.stringify({ event })}`;

describe('IFrameHelper postMessage communication', () => {
  const frameWindow = {};
  let eventHandler;
  let getAppFrameSpy;
  let receivedMessages;

  beforeEach(() => {
    window.$kozmopath = { baseUrl: 'https://widget.example.test/widget' };
    receivedMessages = [];
    IFrameHelper.events['message-received'] = payload => {
      receivedMessages.push(payload);
    };
    getAppFrameSpy = vi
      .spyOn(IFrameHelper, 'getAppFrame')
      .mockReturnValue({ contentWindow: frameWindow });

    vi.spyOn(window, 'addEventListener');
    IFrameHelper.initPostMessageCommunication();
    eventHandler = window.addEventListener.mock.calls.find(
      ([eventName]) => eventName === 'message'
    )[1];
  });

  afterEach(() => {
    delete IFrameHelper.events['message-received'];
    getAppFrameSpy.mockRestore();
    vi.restoreAllMocks();
    window.onmessage = null;
    delete window.$kozmopath;
  });

  it('accepts canonical and legacy message prefixes from the widget frame', () => {
    const expectedOrigin = 'https://widget.example.test';

    eventHandler({
      data: message('chatwoot-widget:'),
      source: frameWindow,
      origin: expectedOrigin,
    });
    eventHandler({
      data: message('kozmopath-widget:'),
      source: frameWindow,
      origin: expectedOrigin,
    });

    expect(receivedMessages).toHaveLength(2);
    expect(receivedMessages[0]).toEqual({ event: 'message-received' });
    expect(receivedMessages[1]).toEqual({ event: 'message-received' });
  });

  it('rejects messages from another source or origin', () => {
    const validEvent = {
      data: message('chatwoot-widget:'),
      source: frameWindow,
      origin: 'https://widget.example.test',
    };

    eventHandler({ ...validEvent, source: {} });
    eventHandler({ ...validEvent, origin: 'https://attacker.example.test' });

    expect(receivedMessages).toHaveLength(0);
  });

  it('ignores malformed JSON without throwing', () => {
    expect(() =>
      eventHandler({
        data: 'chatwoot-widget:{malformed',
        source: frameWindow,
        origin: 'https://widget.example.test',
      })
    ).not.toThrow();
    expect(receivedMessages).toHaveLength(0);
  });

  it('adds a message listener without overwriting an existing onmessage handler', () => {
    const existingHandler = vi.fn();
    window.onmessage = existingHandler;

    IFrameHelper.initPostMessageCommunication();

    expect(window.onmessage).toBe(existingHandler);
    expect(
      window.addEventListener.mock.calls.filter(
        ([eventName]) => eventName === 'message'
      )
    ).toHaveLength(2);
  });
});
