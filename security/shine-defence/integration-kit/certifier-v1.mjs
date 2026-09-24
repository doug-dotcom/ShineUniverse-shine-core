import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { extname, join, relative } from 'node:path';

export const SHINE_DEFENCE_KIT_VERSION = '1.0.0';

export function readUtf8(root, path) {
  return readFileSync(join(root, path), 'utf8');
}

export function createCertification({ root = process.cwd(), appName, contractPath }) {
  if (!appName || !contractPath) throw new Error('Shine Defence certification needs an app name and contract path.');
  const contract = JSON.parse(readUtf8(root, contractPath));
  const results = [];

  function check(id, ok, evidence) {
    results.push({ id, ok: Boolean(ok), evidence: String(evidence || '') });
  }

  function finish() {
    const requiredIds = contract.requirements.filter(item => item.required).map(item => item.id);
    const testedIds = new Set(results.map(item => item.id));
    const untested = requiredIds.filter(id => !testedIds.has(id));
    if (untested.length) {
      results.push({
        id: 'CONTRACT',
        ok: false,
        evidence: 'Required controls without app-specific evidence: ' + untested.join(', ')
      });
    }

    for (const result of results) {
      console.log((result.ok ? 'PASS' : 'FAIL') + ' ' + result.id + ' - ' + result.evidence);
    }

    const failed = results.filter(result => !result.ok);
    if (failed.length) {
      console.error('\nSHINE DEFENCE: FAIL - ' + appName + ' has ' + failed.length + ' failing control' + (failed.length === 1 ? '' : 's') + '.');
      process.exitCode = 1;
      return false;
    }

    console.log('\nSHINE DEFENCE: PASS - ' + appName + ' satisfies ' + contract.contract + '.');
    return true;
  }

  return { contract, check, finish };
}

const secretPatterns = [
  ['private key', /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/],
  ['GitHub classic token', /\bgh[pousr]_[A-Za-z0-9]{30,}\b/],
  ['GitHub fine-grained token', /\bgithub_pat_[A-Za-z0-9_]{30,}\b/],
  ['OpenAI-style secret key', /\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}\b/],
  ['AWS access key', /\bAKIA[0-9A-Z]{16}\b/],
  ['literal Supabase service-role key', /SUPABASE_SERVICE_ROLE_KEY\s*[:=]\s*['"][^'$"{][^'"]{15,}['"]/]
];

const ignoredDirectories = new Set(['.git', 'node_modules', '.next', '.wrangler', 'coverage']);
const textExtensions = new Set([
  '.js', '.mjs', '.cjs', '.ts', '.tsx', '.jsx', '.json', '.yml', '.yaml',
  '.html', '.css', '.md', '.txt', '.toml', '.ini', '.sh'
]);

export function scanForObviousSecrets(root = process.cwd(), paths = ['.']) {
  const hits = [];

  function scan(relativePath) {
    const full = join(root, relativePath);
    if (!existsSync(full)) return;
    const info = statSync(full);

    if (info.isDirectory()) {
      for (const entry of readdirSync(full, { withFileTypes: true })) {
        if (entry.isDirectory() && ignoredDirectories.has(entry.name)) continue;
        scan(join(relativePath, entry.name));
      }
      return;
    }

    if (!info.isFile() || info.size > 5 * 1024 * 1024) return;
    const extension = extname(relativePath);
    const basename = relativePath.split(/[\\/]/).at(-1) || '';
    if (!textExtensions.has(extension) && !basename.startsWith('.env')) return;

    let text;
    try { text = readFileSync(full, 'utf8'); } catch { return; }
    for (const [label, pattern] of secretPatterns) {
      if (pattern.test(text)) {
        hits.push({ path: relative(root, full), label });
        break;
      }
    }
  }

  for (const path of paths) scan(path);
  return hits;
}
