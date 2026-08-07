import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const requiredFiles = [
  'README.md',
  'trial-product-contract.md',
  'structural-divergence.md',
  'implementation-map.md',
  'asset-provenance.json',
  'selection.json',
  'verification-results.json',
  'shared/marketing-base.css',
  'shared/prototype.js',
  'variant-a-direct-trial/index.html',
  'variant-a-direct-trial/styles.css',
  'variant-a-direct-trial/main.js',
  'variant-b-guided/index.html',
  'variant-b-guided/styles.css',
  'variant-b-guided/main.js',
  'signup-companion/index.html',
  'signup-companion/styles.css',
  'signup-companion/main.js',
  'scripts/render.mjs',
  'tests/verify-browser.mjs',
];

const requiredRenders = {
  'renders/variant-a-desktop-1440x900.png': [1440, 900],
  'renders/variant-a-mobile-390x844.png': [390, 844],
  'renders/variant-a-desktop-final-cta.png': [1440, 900],
  'renders/variant-b-desktop-1440x900.png': [1440, 900],
  'renders/variant-b-mobile-390x844.png': [390, 844],
  'renders/variant-b-desktop-final-cta.png': [1440, 900],
  'renders/signup-desktop-1440x900.png': [1440, 900],
  'renders/signup-mobile-390x844.png': [390, 844],
  'renders/desktop-comparison-contact-sheet.png': [1536, 332],
};

const read = relativePath => readFile(path.join(root, relativePath), 'utf8');

for (const file of requiredFiles) {
  await read(file);
}

const [variantA, variantB, signup, selection, provenance] = await Promise.all([
  read('variant-a-direct-trial/index.html'),
  read('variant-b-guided/index.html'),
  read('signup-companion/index.html'),
  read('selection.json').then(JSON.parse),
  read('asset-provenance.json').then(JSON.parse),
]);

for (const [name, html] of [
  ['Variant A', variantA],
  ['Variant B', variantB],
  ['signup companion', signup],
]) {
  assert.equal((html.match(/<h1\b/gi) || []).length, 1, `${name} must have exactly one H1`);
  assert.doesNotMatch(html, /\s(?:src|href)=["']https?:\/\//i, `${name} must not load remote assets`);
  assert.doesNotMatch(html, /\s(?:src|href)=["']\/(?!\/)/i, `${name} must not use production-root asset paths`);
  assert.doesNotMatch(html, /5 dakika|istediğin zaman iptal|sınırsız|limitsiz|\b₺\b/i, `${name} contains an unapproved claim`);
}

for (const [name, html] of [['Variant A', variantA], ['Variant B', variantB]]) {
  const localTrialLinks = [...html.matchAll(/<a\b[^>]*data-trial-cta[^>]*href=["']([^"']+)/gi)];
  assert.ok(localTrialLinks.length >= 2, `${name} needs repeated trial entry points`);
  assert.ok(localTrialLinks.every(match => match[1].includes('../signup-companion/')), `${name} trial CTAs must stay local`);
  assert.match(html, /data-production-href=["']https:\/\/app\.kozmopath\.com\/app\/auth\/signup["']/i);
  assert.match(html, /data-production-href=["']https:\/\/app\.kozmopath\.com\/app\/login["']/i);
}

assert.match(variantA, /Kozmopath’i 14 gün ücretsiz dene — kredi kartı gerekmez\./);
assert.match(variantA, />14 gün ücretsiz dene</);
assert.match(variantA, />14 günlük denemeni başlat</);
assert.match(variantA, /Deneme süren hesabın oluşturulduğunda başlar\. Kredi kartı gerekmez\./);
assert.doesNotMatch(variantA, /class=["'][^"']*trial-runway/);

assert.match(variantB, /class=["'][^"']*trial-runway/);
assert.match(variantB, />14 GÜN</);
assert.match(variantB, />Hesabını oluştur</);
assert.match(variantB, /href=["']#nasil-calisir["']/);
assert.doesNotMatch(variantB, /data-trial-cta=["']hero-primary["']/);

for (const text of [
  '14 GÜNLÜK ÜCRETSİZ DENEME',
  'Kozmopath’ı kendi mağazanla dene.',
  'İş e-postan ve şifren yeterli. Kredi kartı gerekmez.',
  '14 günlük denemeyi başlat',
  'Zaten hesabın var mı? Oturum aç',
  'Deneme süren hesabın oluşturulduğunda başlar.',
]) {
  assert.ok(signup.includes(text), `signup companion is missing: ${text}`);
}
assert.match(signup, /type=["']email["'][^>]*required/i);
assert.match(signup, /type=["']password["'][^>]*required/i);
assert.match(signup, /aria-live=["']polite["']/i);
assert.doesNotMatch(signup, /<form\b[^>]*action=/i, 'prototype form must not have a network action');

assert.equal(selection.selected, 'variant-a-direct-trial');
assert.equal(selection.status, 'selected_approved_for_frontend_implementation');
assert.equal(selection.variant_status['variant-a-direct-trial'], 'selected');
assert.equal(selection.variant_status['variant-b-guided'], 'rejected');
assert.equal(selection.shared_companion, 'signup-companion');
assert.equal(selection.shared_companion_status, 'selected');
assert.ok(Array.isArray(provenance.assets) && provenance.assets.length >= 3);

for (const asset of provenance.assets) {
  const bytes = await readFile(path.join(root, asset.prototype_path));
  const digest = createHash('sha256').update(bytes).digest('hex');
  assert.equal(digest, asset.sha256, `asset hash mismatch: ${asset.prototype_path}`);
}

const htmlFiles = [];
async function collectHtml(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory() && entry.name !== 'renders') await collectHtml(fullPath);
    if (entry.isFile() && entry.name.endsWith('.html')) htmlFiles.push(fullPath);
  }
}
await collectHtml(root);
assert.equal(htmlFiles.length, 3, 'only the two landings and shared signup HTML are expected');

for (const [render, [expectedWidth, expectedHeight]] of Object.entries(requiredRenders)) {
  const bytes = await readFile(path.join(root, render));
  assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', `${render} is not a PNG`);
  assert.equal(bytes.readUInt32BE(16), expectedWidth, `${render} has the wrong width`);
  assert.equal(bytes.readUInt32BE(20), expectedHeight, `${render} has the wrong height`);
}

console.log(`PASS: ${requiredFiles.length} required files, three HTML contracts, and nine render artifacts verified`);
