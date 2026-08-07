import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const agentBrowser = process.env.AGENT_BROWSER_BIN || 'agent-browser';
const baseURL = (process.env.PROTOTYPE_BASE_URL || 'http://127.0.0.1:5089').replace(/\/$/, '');
const session = process.env.AGENT_BROWSER_SESSION || 'kozmopath-trial-verify-001';

const run = (args, options = {}) => execFileSync(
  agentBrowser,
  ['--session', session, ...args],
  { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...options },
).trim();

const evaluate = source => {
  const encoded = Buffer.from(source).toString('base64');
  const output = run(['eval', '-b', encoded, '--json']);
  const result = JSON.parse(output);
  if (result.success === false) throw new Error(result.error || output);
  return result.data?.result ?? result.data ?? result.result;
};

const open = route => {
  run(['open', `${baseURL}/${route}/`, '--args', '--lang=tr-TR']);
  run(['set', 'media', 'light', 'reduced-motion']);
};

const pageAudit = () => evaluate(`(() => {
  const ids = [...document.querySelectorAll('[id]')].map(node => node.id);
  const sections = [...document.querySelectorAll('[data-page-section]')].map(node => {
    const rect = node.getBoundingClientRect();
    return { id: node.id, top: rect.top + scrollY, bottom: rect.bottom + scrollY, height: rect.height };
  });
  const images = [...document.images].map(image => ({ src: image.currentSrc, complete: image.complete, width: image.naturalWidth }));
  return {
    lang: document.documentElement.lang,
    h1: document.querySelectorAll('h1').length,
    duplicateIds: ids.filter((id, index) => ids.indexOf(id) !== index),
    images,
    remoteResources: [...document.querySelectorAll('[src], link[href], script[src]')].map(node => node.src || node.href).filter(url => /^https?:/.test(url) && !url.startsWith(location.origin)),
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    ctas: [...document.querySelectorAll('[data-trial-cta]')].map(node => ({ href: node.href, target: node.dataset.productionHref })),
    loginTargets: [...document.querySelectorAll('[data-production-href$="/app/login"]')].map(node => node.dataset.productionHref),
    sections,
    reducedMotion: getComputedStyle(document.documentElement).scrollBehavior,
  };
})()`);

try {
  for (const route of ['variant-a-direct-trial', 'variant-b-guided']) {
    open(route);
    run(['set', 'viewport', '1440', '900']);
    run(['wait', '200']);
    const audit = pageAudit();
    assert.equal(audit.lang, 'tr');
    assert.equal(audit.h1, 1);
    assert.deepEqual(audit.duplicateIds, []);
    assert.ok(audit.images.every(image => image.complete && image.width > 0), `${route}: broken image`);
    assert.deepEqual(audit.remoteResources, [], `${route}: remote subresource`);
    assert.ok(audit.overflow <= 1, `${route}: horizontal overflow ${audit.overflow}px`);
    assert.ok(audit.ctas.length >= 2 && audit.ctas.every(cta => cta.href.startsWith(`${baseURL}/signup-companion/`)));
    assert.ok(audit.ctas.every(cta => cta.target === 'https://app.kozmopath.com/app/auth/signup'));
    assert.ok(audit.loginTargets.length >= 2 && audit.loginTargets.every(target => target === 'https://app.kozmopath.com/app/login'));
    assert.equal(audit.reducedMotion, 'auto');
    assert.ok(audit.sections.every(section => section.height > 0));
    for (let index = 1; index < audit.sections.length; index += 1) {
      assert.ok(audit.sections[index].top >= audit.sections[index - 1].bottom - 2, `${route}: sections overlap near ${audit.sections[index].id}`);
    }

    run(['click', '[data-trial-cta]']);
    run(['wait', '150']);
    assert.match(run(['get', 'url']), new RegExp(`${baseURL}/signup-companion/`));
    run(['back']);
    run(['wait', '150']);

    run(['set', 'viewport', '390', '844']);
    run(['click', 'summary']);
    const menu = evaluate(`(() => { const details = document.querySelector('.mobile-menu'); const rect = details.querySelector('nav').getBoundingClientRect(); return { open: details.open, left: rect.left, right: rect.right, viewport: innerWidth }; })()`);
    assert.equal(menu.open, true);
    assert.ok(menu.left >= 0 && menu.right <= menu.viewport, `${route}: mobile menu is clipped`);
    assert.ok(pageAudit().overflow <= 1, `${route}: mobile overflow`);

    const consoleOutput = run(['console']);
    const errorOutput = run(['errors']);
    assert.doesNotMatch(consoleOutput, /\berror\b|failed to load/i, `${route}: console error`);
    assert.doesNotMatch(errorOutput, /\berror\b|failed/i, `${route}: page error`);
  }

  open('signup-companion');
  run(['set', 'viewport', '1440', '900']);
  run(['wait', '150']);
  const signupAudit = evaluate(`(() => {
    const focusable = [...document.querySelectorAll('a[href], button:not([disabled]), input:not([disabled])')].filter(node => getComputedStyle(node).display !== 'none').map(node => node.id || node.textContent.trim());
    return {
      h1: document.querySelectorAll('h1').length,
      overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      remote: [...document.querySelectorAll('[src], link[href], script[src]')].map(node => node.src || node.href).filter(url => /^https?:/.test(url) && !url.startsWith(location.origin)),
      action: document.querySelector('form').getAttribute('action'),
      method: document.querySelector('form').getAttribute('method'),
      focusable,
      images: [...document.images].every(image => image.complete && image.naturalWidth > 0),
    };
  })()`);
  assert.equal(signupAudit.h1, 1);
  assert.ok(signupAudit.overflow <= 1);
  assert.deepEqual(signupAudit.remote, []);
  assert.equal(signupAudit.action, null);
  assert.equal(signupAudit.method, null);
  assert.equal(signupAudit.images, true);
  assert.ok(signupAudit.focusable.indexOf('business-email') < signupAudit.focusable.indexOf('password'));
  assert.ok(signupAudit.focusable.indexOf('password') < signupAudit.focusable.indexOf('toggle-password'));

  run(['click', 'button[type="submit"]']);
  let validation = evaluate(`({ email: document.querySelector('#email-error').textContent, focused: document.activeElement.id })`);
  assert.equal(validation.focused, 'business-email');
  assert.ok(validation.email.length > 0);

  run(['fill', '#business-email', 'owner@magaza.example']);
  run(['fill', '#password', 'short']);
  run(['click', 'button[type="submit"]']);
  validation = evaluate(`({ password: document.querySelector('#password-error').textContent, focused: document.activeElement.id })`);
  assert.equal(validation.focused, 'password');
  assert.ok(validation.password.length > 0);

  run(['click', '#toggle-password']);
  assert.equal(evaluate(`document.querySelector('#password').type`), 'text');
  assert.equal(evaluate(`document.querySelector('#toggle-password').getAttribute('aria-pressed')`), 'true');
  run(['click', '#toggle-password']);
  assert.equal(evaluate(`document.querySelector('#password').type`), 'password');

  run(['fill', '#password', 'Password1!']);
  run(['network', 'requests', '--clear']);
  run(['click', 'button[type="submit"]']);
  assert.equal(evaluate(`document.querySelector('button[type="submit"]').dataset.pending`), 'true');
  run(['wait', '500']);
  assert.equal(evaluate(`document.querySelector('#form-status').textContent`), 'Tasarım prototipi: production entegrasyonunda gerçek signup akışına bağlanacak.');
  const networkOutput = run(['network', 'requests']);
  assert.doesNotMatch(networkOutput, /POST|PUT|PATCH|DELETE|accounts\.json|auth\/signup/i, 'signup prototype emitted a request');

  run(['set', 'viewport', '390', '844']);
  const mobileAudit = evaluate(`({ overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth, formTop: document.querySelector('.signup-form-plane').getBoundingClientRect().top, proofTop: document.querySelector('.signup-proof-plane').getBoundingClientRect().top + scrollY, formBottom: document.querySelector('.signup-form-plane').getBoundingClientRect().bottom + scrollY })`);
  assert.ok(mobileAudit.overflow <= 1);
  assert.equal(mobileAudit.formTop, 0);
  assert.ok(mobileAudit.proofTop >= mobileAudit.formBottom - 1, 'mobile proof must follow the form plane');

  const consoleOutput = run(['console']);
  const errorOutput = run(['errors']);
  assert.doesNotMatch(consoleOutput, /\berror\b|failed to load/i);
  assert.doesNotMatch(errorOutput, /\berror\b|failed/i);

  console.log('PASS: desktop/mobile browser geometry, local navigation, form states, and zero-request signup behavior verified');
} finally {
  try { run(['close']); } catch { /* session may already be closed */ }
}
