# Lingma Backup Rotation Design

**Date:** 2026-03-18

## Goal

Make the installer resilient when users upgrade Lingma and run the patch script again, even if the existing `workbench.desktop.main.js` still contains the patch marker or old backup metadata no longer matches the current bundle.

## Problem

The current installer uses a fixed backup path and treats `PATCH_MARKER` as the only source of truth. That creates a false terminal state:

- users update Lingma
- `workbench.desktop.main.js` changes
- older backup/meta files remain next to the bundle
- the installer sees a marker and returns `Already patched`

This blocks a valid reinstall and leaves `restore` semantics ambiguous.

## Design

### Active Backup Set

Keep one active backup pair with stable paths:

- `workbench.desktop.main.js.lingma-auto-resume.backup`
- `workbench.desktop.main.js.lingma-auto-resume.meta.json`

`restore` always uses the active backup pair only.

### Archived Backup Sets

When the installer needs to replace the active backup set, it first archives the current active files with a timestamp suffix:

- `...backup.<timestamp>`
- `...meta.json.<timestamp>`

This preserves history without changing the normal `restore` path.

### State Model

Before `install`, the script computes a structured state from the target bundle, backup, and metadata:

- `clean`
  - target exists
  - target does not contain the patch marker
  - no current integrity conflict requiring rotation
- `patched-current`
  - target contains the patch marker
  - metadata exists
  - target sha matches `patchedSha256`
  - backup sha matches `sourceSha256`
- `patched-stale`
  - target contains the patch marker
  - metadata is missing or sha values do not match the current active files
- `drifted`
  - target does not contain the patch marker
  - active backup/meta exist, but they do not describe the current target generation

`status` should expose this computed state directly so users can see why the installer will or will not reinstall.

### Install Behavior

For each state:

- `clean`
  - if no active backup exists, create it from the current target
  - if an old active backup exists but belongs to a previous generation, archive it first
  - patch the current target
  - rewrite active metadata
- `patched-current`
  - do not modify files
  - report `Already patched`
- `patched-stale`
  - archive the active backup/meta if present
  - treat the current target as the new source generation
  - create a fresh active backup from the current target
  - patch the target and rewrite metadata
- `drifted`
  - archive the active backup/meta if present
  - treat the current target as the new source generation
  - create a fresh active backup from the current target
  - patch the target and rewrite metadata

### Metadata

The metadata file remains the source of integrity checks for the active generation and should include:

- `scriptVersion`
- `patchMarker`
- `targetFile`
- `backupFile`
- `createdAt`
- `sourceSha256`
- `patchedSha256`
- `state` or enough fields for the script to recompute it

Archived metadata files do not need special indexing; the timestamped filename is sufficient.

## Restore Semantics

`restore` restores from the active backup only. Archived backups are retained for manual recovery but are not part of the default restore flow.

## User-Facing Changes

### Installer output

The script should stop using a raw marker check as the `Already patched` gate. Instead:

- report `Already patched` only for `patched-current`
- report when an old generation was archived
- report when a fresh active backup was created for the current bundle

### README

Document:

- active backup paths
- archived backup naming
- the meaning of `patched-current`, `patched-stale`, and `drifted`
- reinstall behavior after Lingma upgrades

## Non-Goals

- supporting arbitrary bundle structures beyond the known patch target
- automatic restore from archived generations
- maintaining more than one active restore target
