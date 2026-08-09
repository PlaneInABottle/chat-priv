import { dispatchWindowEvent } from '../CustomEventHelper';

describe('dispatchWindowEvent', () => {
  it('dispatches branded and upstream-compatible widget events', () => {
    window.dispatchEvent = vi.fn();
    dispatchWindowEvent({ eventName: 'kozmopath:ready' });

    expect(window.dispatchEvent).toHaveBeenCalledTimes(2);
    expect(
      window.dispatchEvent.mock.calls.map(([event]) => event.type)
    ).toEqual(['kozmopath:ready', 'chatwoot:ready']);
  });
});
