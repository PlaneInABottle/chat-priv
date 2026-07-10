import {
  buildTextSetupProgress,
  buildVoiceSetupProgress,
} from './setupProgress';

const agent = ({ id, checks = {}, lifecycleStatus = 'draft' }) => ({
  id,
  lifecycle_status: lifecycleStatus,
  readiness: {
    checks: Object.entries(checks).map(([key, complete]) => ({
      key,
      complete,
    })),
  },
});

describe('AI setup progress', () => {
  it('starts with every Text AI step incomplete when no assistant exists', () => {
    const progress = buildTextSetupProgress([]);

    expect(progress.agent).toBeNull();
    expect(progress.completedCount).toBe(0);
    expect(progress.ready).toBe(false);
    expect(progress.steps.every(step => !step.complete)).toBe(true);
  });

  it('recognizes a fully active Text AI assistant', () => {
    const progress = buildTextSetupProgress([
      agent({
        id: 1,
        lifecycleStatus: 'active',
        checks: { instructions: true, inbox: true, test: true },
      }),
    ]);

    expect(progress.completedCount).toBe(5);
    expect(progress.ready).toBe(true);
  });

  it('requires both a greeting and instructions for Voice AI guidance', () => {
    const progress = buildVoiceSetupProgress([
      agent({
        id: 2,
        checks: {
          greeting: false,
          instructions: true,
          inbox: true,
          test: true,
        },
      }),
    ]);

    expect(progress.steps.find(step => step.key === 'instructions')).toEqual({
      key: 'instructions',
      complete: false,
    });
  });

  it('uses one assistant instead of combining progress across assistants', () => {
    const progress = buildTextSetupProgress([
      agent({ id: 1, checks: { instructions: true } }),
      agent({ id: 2, checks: { inbox: true, test: true } }),
    ]);

    expect(progress.agent.id).toBe(2);
    expect(
      progress.steps.find(step => step.key === 'instructions').complete
    ).toBe(false);
  });
});
