const readinessMap = agent =>
  new Map(
    (agent?.readiness?.checks || []).map(check => [
      check.key,
      Boolean(check.complete),
    ])
  );

const scoreAgent = (agent, requiredChecks) => {
  const checks = readinessMap(agent);
  const readinessScore = requiredChecks.filter(key => checks.get(key)).length;
  return readinessScore + (agent.lifecycle_status === 'active' ? 1 : 0);
};

const selectMostAdvancedAgent = (agents, requiredChecks) =>
  [...agents].sort(
    (first, second) =>
      scoreAgent(second, requiredChecks) - scoreAgent(first, requiredChecks)
  )[0] || null;

const isStepComplete = (step, agent, checks) => {
  if (step.type === 'created') return Boolean(agent);
  if (step.type === 'active') return agent?.lifecycle_status === 'active';
  return step.checks.every(key => checks.get(key));
};

const buildProgress = (agents, definitions) => {
  const requiredChecks = definitions.flatMap(step => step.checks || []);
  const agent = selectMostAdvancedAgent(agents, requiredChecks);
  const checks = readinessMap(agent);
  const steps = definitions.map(step => ({
    key: step.key,
    complete: isStepComplete(step, agent, checks),
  }));

  return {
    agent,
    steps,
    completedCount: steps.filter(step => step.complete).length,
    ready: steps.every(step => step.complete),
  };
};

export const buildTextSetupProgress = agents =>
  buildProgress(agents, [
    { key: 'assistant', type: 'created' },
    { key: 'instructions', checks: ['instructions'] },
    { key: 'inbox', checks: ['inbox'] },
    { key: 'test', checks: ['test'] },
    { key: 'active', type: 'active' },
  ]);

export const buildVoiceSetupProgress = agents =>
  buildProgress(agents, [
    { key: 'assistant', type: 'created' },
    { key: 'instructions', checks: ['greeting', 'instructions'] },
    { key: 'inbox', checks: ['inbox'] },
    { key: 'test', checks: ['test'] },
    { key: 'active', type: 'active' },
  ]);
