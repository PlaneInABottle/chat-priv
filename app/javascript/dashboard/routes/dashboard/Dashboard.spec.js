import Dashboard from './Dashboard.vue';
import wootConstants from 'dashboard/constants/globals';

const updateLayout = Dashboard.watch.isSmallScreen.handler;

describe('Dashboard.vue display layout watcher', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('does not persist an empty desktop layout on initial load', () => {
    window.innerWidth = wootConstants.SMALL_SCREEN_BREAKPOINT + 1;
    const updateUISettings = vi.fn();

    updateLayout.call({
      previouslyUsedDisplayType: undefined,
      updateUISettings,
    });

    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('restores a previously used desktop layout', () => {
    window.innerWidth = wootConstants.SMALL_SCREEN_BREAKPOINT + 1;
    const updateUISettings = vi.fn();

    updateLayout.call({
      previouslyUsedDisplayType: wootConstants.LAYOUT_TYPES.CONDENSED,
      updateUISettings,
    });

    expect(updateUISettings).toHaveBeenCalledWith({
      conversation_display_type: wootConstants.LAYOUT_TYPES.CONDENSED,
    });
  });

  it('uses the expanded layout on small screens', () => {
    window.innerWidth = wootConstants.SMALL_SCREEN_BREAKPOINT;
    const updateUISettings = vi.fn();

    updateLayout.call({
      previouslyUsedDisplayType: undefined,
      updateUISettings,
    });

    expect(updateUISettings).toHaveBeenCalledWith({
      conversation_display_type: wootConstants.LAYOUT_TYPES.EXPANDED,
    });
  });
});
