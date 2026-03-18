# Lingma Backup Rotation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add generation-aware backup rotation so Lingma upgrades can be patched again without getting stuck on a false `Already patched` result.

**Architecture:** Extend the installer with an explicit state-analysis step that compares the target bundle, active backup, and metadata hashes before deciding whether to skip, rotate, back up, or patch. Keep one active backup pair for normal restore and archive replaced generations with timestamped filenames.

**Tech Stack:** Bash, embedded Node.js helpers, markdown docs

---

### Task 1: Add regression coverage for install state handling

**Files:**
- Create: `tests/lingma-patch.test.js`
- Modify: `package.json` if a simple test runner shim is needed
- Test: `tests/lingma-patch.test.js`

**Step 1: Write the failing test**

Write integration-style tests that execute `lingma-patch.sh` against temporary fixture bundles and assert:

- `status` reports `patched-current` when target, backup, and meta match
- `install` rotates stale active backup/meta when marker exists but hashes mismatch
- `install` rotates drifted active backup/meta when target changed and marker is absent

**Step 2: Run test to verify it fails**

Run: `node tests/lingma-patch.test.js`
Expected: FAIL because the current script does not expose the new state model or archive stale generations.

**Step 3: Write minimal implementation**

Add just enough state-analysis and archive behavior in the installer for the failing assertions to pass.

**Step 4: Run test to verify it passes**

Run: `node tests/lingma-patch.test.js`
Expected: PASS

**Step 5: Commit**

```bash
git add tests/lingma-patch.test.js lingma-patch.sh
git commit -m "feat: rotate stale lingma backups"
```

### Task 2: Implement generation-aware backup and archive helpers

**Files:**
- Modify: `lingma-patch.sh`
- Test: `tests/lingma-patch.test.js`

**Step 1: Write the failing test**

Add a focused test that proves archive file names are created before the active backup/meta are replaced.

**Step 2: Run test to verify it fails**

Run: `node tests/lingma-patch.test.js`
Expected: FAIL because the current installer only keeps a single fixed backup/meta pair.

**Step 3: Write minimal implementation**

Add helper functions for:

- computing archive paths with timestamps
- rotating the current active backup/meta
- preparing a fresh active backup from the current target

**Step 4: Run test to verify it passes**

Run: `node tests/lingma-patch.test.js`
Expected: PASS

**Step 5: Commit**

```bash
git add tests/lingma-patch.test.js lingma-patch.sh
git commit -m "feat: archive replaced lingma backups"
```

### Task 3: Expose the new status model and document it

**Files:**
- Modify: `lingma-patch.sh`
- Modify: `README.md`
- Test: `tests/lingma-patch.test.js`

**Step 1: Write the failing test**

Add assertions for the JSON returned by `status`, including the explicit `state` field and any archive reporting needed by tests.

**Step 2: Run test to verify it fails**

Run: `node tests/lingma-patch.test.js`
Expected: FAIL because `status` currently exposes booleans only.

**Step 3: Write minimal implementation**

Update the Node status helper and README so users can understand:

- what state they are in
- when the installer archives old generations
- which backup `restore` uses

**Step 4: Run test to verify it passes**

Run: `node tests/lingma-patch.test.js`
Expected: PASS

**Step 5: Commit**

```bash
git add README.md tests/lingma-patch.test.js lingma-patch.sh
git commit -m "docs: describe lingma backup generations"
```
