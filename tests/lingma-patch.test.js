const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const SCRIPT_PATH = path.join(__dirname, '..', 'lingma-patch.sh');
const PATCH_MARKER = '[LingmaAutoResumePatch]';
const BACKUP_SUFFIX = '.lingma-auto-resume.backup';
const META_SUFFIX = '.lingma-auto-resume.meta.json';

const PATCH_TARGET_SNIPPET =
  'const c=(0,GF.useCallback)(()=>{l(!0);const d=t.permissionRequest;if(!d){r.warn("[ResumeTool] No permission request found");return}const g=d.options?.[0];if(!g){r.warn("[ResumeTool] No allow option found");return}r.trace("[ResumeTool] Resuming task with option:",g),e.get("IACPClientService").resolvePermissionRequest(t.toolCallId,g),e.get("IChatSessionService").resumeSession(t.permissionRequest?.sessionId||t.sessionId,t.permissionRequest),r.info("[ResumeTool] Session resumed")},[t,e]),u=(0,GF.useMemo)(()=>[mt.FINISHED,mt.ERROR,mt.CANCELLED].includes(t.toolCallStatus),[t.toolCallStatus]);';

function buildBundle(versionTag) {
  return [
    `/* bundle ${versionTag} */`,
    'function installableBundle(){',
    PATCH_TARGET_SNIPPET,
    'return "ok";',
    '}',
    '',
  ].join('\n');
}

function parseTrailingJson(output) {
  const match = output.match(/\{[\s\S]*\}\s*$/);
  assert(match, `Expected JSON output, got:\n${output}`);
  return JSON.parse(match[0]);
}

function runScript(args, expectedExitCode = 0) {
  const result = spawnSync('bash', [SCRIPT_PATH, ...args], {
    encoding: 'utf8',
  });

  if (result.status !== expectedExitCode) {
    throw new Error(
      `Command failed with exit code ${result.status}\n` +
        `STDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`
    );
  }

  return result;
}

function createFixture() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'lingma-patch-test-'));
  const targetFile = path.join(tempDir, 'workbench.desktop.main.js');
  return {
    tempDir,
    targetFile,
    backupFile: `${targetFile}${BACKUP_SUFFIX}`,
    metaFile: `${targetFile}${META_SUFFIX}`,
  };
}

function listArchivedFiles(file) {
  const dir = path.dirname(file);
  const prefix = `${path.basename(file)}.`;
  return fs
    .readdirSync(dir)
    .filter((entry) => entry.startsWith(prefix))
    .sort();
}

function install(targetFile) {
  return runScript(['install', '--file', targetFile, '--force']);
}

function status(targetFile) {
  const result = runScript(['status', '--file', targetFile]);
  return parseTrailingJson(result.stdout);
}

function testPatchedCurrentState() {
  const fixture = createFixture();
  fs.writeFileSync(fixture.targetFile, buildBundle('v1'));

  install(fixture.targetFile);

  const currentStatus = status(fixture.targetFile);

  assert.strictEqual(currentStatus.state, 'patched-current');
  assert.strictEqual(currentStatus.backupExists, true);
  assert.strictEqual(currentStatus.metaExists, true);
  assert.strictEqual(currentStatus.patched, true);
}

function testPatchedStaleRotation() {
  const fixture = createFixture();
  const source = buildBundle('v1');
  fs.writeFileSync(fixture.targetFile, source);

  install(fixture.targetFile);
  fs.writeFileSync(fixture.backupFile, 'stale backup content\n');

  const staleStatus = status(fixture.targetFile);
  assert.strictEqual(staleStatus.state, 'patched-stale');

  const reinstallResult = install(fixture.targetFile);
  const currentStatus = parseTrailingJson(reinstallResult.stdout);

  assert.strictEqual(currentStatus.state, 'patched-current');
  assert.strictEqual(fs.readFileSync(fixture.backupFile, 'utf8'), source);
  assert.strictEqual(fs.readFileSync(fixture.backupFile, 'utf8').includes(PATCH_MARKER), false);
  assert.ok(listArchivedFiles(fixture.backupFile).length >= 1, 'expected archived backup file');
  assert.ok(listArchivedFiles(fixture.metaFile).length >= 1, 'expected archived meta file');
}

function testDriftedRotation() {
  const fixture = createFixture();
  const sourceV1 = buildBundle('v1');
  const sourceV2 = buildBundle('v2');
  fs.writeFileSync(fixture.targetFile, sourceV1);

  install(fixture.targetFile);
  fs.writeFileSync(fixture.targetFile, sourceV2);

  const driftedStatus = status(fixture.targetFile);
  assert.strictEqual(driftedStatus.state, 'drifted');

  const reinstallResult = install(fixture.targetFile);
  const currentStatus = parseTrailingJson(reinstallResult.stdout);

  assert.strictEqual(currentStatus.state, 'patched-current');
  assert.strictEqual(fs.readFileSync(fixture.backupFile, 'utf8'), sourceV2);
  assert.ok(listArchivedFiles(fixture.backupFile).length >= 1, 'expected archived backup after drift');
  assert.ok(listArchivedFiles(fixture.metaFile).length >= 1, 'expected archived meta after drift');
}

const tests = [
  ['status returns patched-current after a normal install', testPatchedCurrentState],
  ['install rotates stale active backup metadata when target is already patched', testPatchedStaleRotation],
  ['install rotates drifted active backup metadata after the bundle changes', testDriftedRotation],
];

let failures = 0;

for (const [name, testFn] of tests) {
  try {
    testFn();
    process.stdout.write(`PASS ${name}\n`);
  } catch (error) {
    failures += 1;
    process.stderr.write(`FAIL ${name}\n${error.stack}\n`);
  }
}

if (failures > 0) {
  process.exit(1);
}
