import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const renderDirectory = path.join(root, 'renders');
const baseURL = (process.env.PROTOTYPE_BASE_URL || 'http://127.0.0.1:5089').replace(/\/$/, '');
const agentBrowser = process.env.AGENT_BROWSER_BIN || 'agent-browser';
const session = process.env.AGENT_BROWSER_SESSION || 'kozmopath-trial-render-001';

const run = args => execFileSync(agentBrowser, ['--session', session, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const open = route => {
  run(['open', `${baseURL}/${route}/`, '--args', '--lang=tr-TR']);
  run(['set', 'media', 'light', 'reduced-motion']);
  run(['wait', '500']);
};
const screenshot = (name, full = false) => run(['screenshot', ...(full ? ['--full'] : []), path.join(renderDirectory, name)]);

try {
  for (const [route, prefix] of [
    ['variant-a-direct-trial', 'variant-a'],
    ['variant-b-guided', 'variant-b'],
  ]) {
    open(route);
    run(['set', 'viewport', '1440', '900']);
    run(['reload']);
    run(['wait', '500']);
    screenshot(`${prefix}-desktop-1440x900.png`);
    run(['scrollintoview', '#final-cta']);
    run(['wait', '100']);
    screenshot(`${prefix}-desktop-final-cta.png`);
    run(['set', 'viewport', '390', '844']);
    run(['reload']);
    run(['eval', 'window.scrollTo(0, 0)']);
    run(['wait', '500']);
    screenshot(`${prefix}-mobile-390x844.png`);
  }

  open('signup-companion');
  run(['set', 'viewport', '1440', '900']);
  run(['reload']);
  run(['wait', '500']);
  screenshot('signup-desktop-1440x900.png');
  run(['set', 'viewport', '390', '844']);
  run(['reload']);
  run(['wait', '500']);
  screenshot('signup-mobile-390x844.png');
} finally {
  try { run(['close']); } catch { /* session may already be closed */ }
}

execFileSync('montage', [
  path.join(renderDirectory, 'variant-a-desktop-1440x900.png'),
  path.join(renderDirectory, 'variant-b-desktop-1440x900.png'),
  path.join(renderDirectory, 'signup-desktop-1440x900.png'),
  '-thumbnail', '480x300^',
  '-gravity', 'center',
  '-extent', '480x300',
  '-background', '#10211f',
  '-tile', '3x1',
  '-geometry', '+16+16',
  path.join(renderDirectory, 'desktop-comparison-contact-sheet.png'),
]);

console.log(`PASS: eight required renders plus contact sheet written to ${renderDirectory}`);
