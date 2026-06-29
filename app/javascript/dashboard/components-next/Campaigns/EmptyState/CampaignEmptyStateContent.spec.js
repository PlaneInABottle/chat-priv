import { describe, it, expect } from 'vitest';
import {
  ONGOING_CAMPAIGN_EMPTY_STATE_CONTENT,
  ONE_OFF_CAMPAIGN_EMPTY_STATE_CONTENT,
} from './CampaignEmptyStateContent.js';

describe('CampaignEmptyStateContent.js', () => {
  it('does not contain hardcoded PaperLayer brand name', () => {
    const allNames = [
      ...ONGOING_CAMPAIGN_EMPTY_STATE_CONTENT,
      ...ONE_OFF_CAMPAIGN_EMPTY_STATE_CONTENT,
    ].map(c => c.inbox?.name);

    allNames.forEach(name => {
      expect(name).not.toMatch(/PaperLayer/i);
    });
  });

  it('does not contain hardcoded Kozmopath brand name or URLs', () => {
    const allContent = JSON.stringify([
      ...ONGOING_CAMPAIGN_EMPTY_STATE_CONTENT,
      ...ONE_OFF_CAMPAIGN_EMPTY_STATE_CONTENT,
    ]);

    expect(allContent).not.toMatch(/kozmopath/i);
  });

  it('uses generic inbox names', () => {
    const webNames = ONGOING_CAMPAIGN_EMPTY_STATE_CONTENT.map(
      c => c.inbox?.name
    );
    const mobileNames = ONE_OFF_CAMPAIGN_EMPTY_STATE_CONTENT.map(
      c => c.inbox?.name
    );

    webNames.forEach(n => expect(n).toBe('Website Inbox'));
    mobileNames.forEach(n => expect(n).toBe('Mobile Inbox'));
  });
});
