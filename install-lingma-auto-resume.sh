#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="1.1.1"
PATCH_MARKER="[LingmaAutoResumePatch]"
BACKUP_SUFFIX=".lingma-auto-resume.backup"
META_SUFFIX=".lingma-auto-resume.meta.json"

usage() {
  cat <<'EOF'
Usage:
  install-lingma-auto-resume.sh [install] [--file <path>] [--force]
  install-lingma-auto-resume.sh restore [--file <path>] [--force]
  install-lingma-auto-resume.sh status  [--file <path>]
  install-lingma-auto-resume.sh help

Commands:
  install   Back up the target bundle and install the auto-resume patch. This is the default command.
  restore   Restore the target bundle from the backup created by install.
  status    Show whether the target bundle is patched and whether a backup exists.

Options:
  --file    Override the target workbench.desktop.main.js path.
  --force   Skip the "Lingma is running" safety check.
EOF
}

log() {
  printf '%s\n' "$*"
}

error() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || error "Missing required command: $1"
}

detect_platform() {
  case "$(uname -s)" in
    Darwin)
      printf 'macos\n'
      ;;
    MINGW* | MSYS* | CYGWIN*)
      printf 'windows\n'
      ;;
    *)
      printf 'unknown\n'
      ;;
  esac
}

windows_path_to_posix() {
  printf '%s' "$1" | sed -E 's#^([A-Za-z]):#/\L\1#; s#\\#/#g'
}

detect_default_target() {
  local platform="$1"
  case "$platform" in
    macos)
      printf '/Applications/Lingma.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js\n'
      ;;
    windows)
      local raw_local_appdata=""
      raw_local_appdata="$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r' | tr -d '\n' || true)"
      if [[ -n "$raw_local_appdata" && "$raw_local_appdata" != "%LOCALAPPDATA%" ]]; then
        printf '%s/Programs/Lingma/resources/app/out/vs/workbench/workbench.desktop.main.js\n' "$(windows_path_to_posix "$raw_local_appdata")"
      else
        error "Cannot resolve %LOCALAPPDATA%. Please pass --file explicitly."
      fi
      ;;
    *)
      error "Unsupported platform: $(uname -s). Please pass --file explicitly on a supported bash environment."
      ;;
  esac
}

is_lingma_running() {
  local platform="$1"
  case "$platform" in
    macos)
      pgrep -if 'Lingma' >/dev/null 2>&1
      ;;
    windows)
      tasklist.exe 2>/dev/null | grep -iq 'Lingma\.exe'
      ;;
    *)
      return 1
      ;;
  esac
}

bundle_backup_path() {
  printf '%s%s\n' "$1" "$BACKUP_SUFFIX"
}

bundle_meta_path() {
  printf '%s%s\n' "$1" "$META_SUFFIX"
}

node_status() {
  local target_file="$1"
  local backup_file="$2"
  local meta_file="$3"

  TARGET_FILE="$target_file" \
  BACKUP_FILE="$backup_file" \
  META_FILE="$meta_file" \
  PATCH_MARKER="$PATCH_MARKER" \
  node <<'NODE'
const fs = require('fs');
const crypto = require('crypto');

const targetFile = process.env.TARGET_FILE;
const backupFile = process.env.BACKUP_FILE;
const metaFile = process.env.META_FILE;
const marker = process.env.PATCH_MARKER;

function sha256(content) {
  return crypto.createHash('sha256').update(content).digest('hex');
}

function readIfExists(file) {
  if (!file || !fs.existsSync(file)) return null;
  return fs.readFileSync(file, 'utf8');
}

const content = readIfExists(targetFile);
const backupContent = readIfExists(backupFile);
const metaExists = fs.existsSync(metaFile);

const status = {
  targetFile,
  targetExists: content !== null,
  patched: content !== null && content.includes(marker),
  backupExists: backupContent !== null,
  metaExists,
  patchMarker: marker,
};

if (content !== null) {
  status.targetSha256 = sha256(content);
}

if (backupContent !== null) {
  status.backupSha256 = sha256(backupContent);
}

if (metaExists) {
  try {
    status.meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
  } catch (error) {
    status.metaReadError = String(error && error.message ? error.message : error);
  }
}

process.stdout.write(JSON.stringify(status, null, 2));
NODE
}

install_patch() {
  local target_file="$1"
  local backup_file="$2"
  local meta_file="$3"
  local tmp_file="$4"

  TARGET_FILE="$target_file" \
  OUTPUT_FILE="$tmp_file" \
  PATCH_MARKER="$PATCH_MARKER" \
  SCRIPT_VERSION="$SCRIPT_VERSION" \
  node <<'NODE'
const fs = require('fs');

const targetFile = process.env.TARGET_FILE;
const outputFile = process.env.OUTPUT_FILE;
const marker = process.env.PATCH_MARKER;
const scriptVersion = process.env.SCRIPT_VERSION;

const original = fs.readFileSync(targetFile, 'utf8');

if (original.includes(marker)) {
  fs.writeFileSync(outputFile, original);
  process.stdout.write('already-patched\n');
  process.exit(0);
}

const pattern = /const c=\(0,GF\.useCallback\)\(\(\)=>\{l\(!0\);const d=t\.permissionRequest;if\(!d\)\{r\.warn\("\[ResumeTool\] No permission request found"\);return\}const g=d\.options\?\.\[0\];if\(!g\)\{r\.warn\("\[ResumeTool\] No allow option found"\);return\}r\.trace\("\[ResumeTool\] Resuming task with option:",g\),e\.get\("IACPClientService"\)\.resolvePermissionRequest\(t\.toolCallId,g\),e\.get\("IChatSessionService"\)\.resumeSession\(t\.permissionRequest\?\.sessionId\|\|t\.sessionId,t\.permissionRequest\),r\.info\("\[ResumeTool\] Session resumed"\)\},\[t,e\]\),u=\(0,GF\.useMemo\)\(\(\)=>\[mt\.FINISHED,mt\.ERROR,mt\.CANCELLED\]\.includes\(t\.toolCallStatus\),\[t\.toolCallStatus\]\);/;

if (!pattern.test(original)) {
  process.stderr.write('Patch target not found. This Lingma bundle version is not supported by this installer.\n');
  process.exit(2);
}

const replacement = `const f=(0,GF.useRef)(!1),c=(0,GF.useCallback)(()=>{const d=t.permissionRequest;if(!d){r.warn("[ResumeTool] No permission request found");return}const g=d.options?.[0];if(!g){r.warn("[ResumeTool] No allow option found");return}r.trace("[ResumeTool] Resuming task with option:",g),e.get("IACPClientService").resolvePermissionRequest(t.toolCallId,g),e.get("IChatSessionService").resumeSession(t.permissionRequest?.sessionId||t.sessionId,t.permissionRequest),l(!0),r.info("[ResumeTool] Session resumed"),r.info("${marker} v${scriptVersion} auto-resume dispatched and footer hidden")},[t,e]);(0,GF.useEffect)(()=>{if(f.current||t.parameters?.reasonForCode!==80408||!t.permissionRequest||[mt.FINISHED,mt.ERROR,mt.CANCELLED].includes(t.toolCallStatus))return;f.current=!0,Promise.resolve().then(()=>c())},[t.parameters?.reasonForCode,t.permissionRequest,t.toolCallStatus,c]);const u=(0,GF.useMemo)(()=>[mt.FINISHED,mt.ERROR,mt.CANCELLED].includes(t.toolCallStatus),[t.toolCallStatus]);`;

const patched = original.replace(pattern, replacement);

if (patched === original) {
  process.stderr.write('Patch replacement made no changes.\n');
  process.exit(3);
}

if (!patched.includes(marker)) {
  process.stderr.write('Patched output is missing the patch marker.\n');
  process.exit(4);
}

fs.writeFileSync(outputFile, patched);
process.stdout.write('patched\n');
NODE

  cp -p "$tmp_file" "$target_file"

  TARGET_FILE="$target_file" \
  BACKUP_FILE="$backup_file" \
  META_FILE="$meta_file" \
  PATCH_MARKER="$PATCH_MARKER" \
  SCRIPT_VERSION="$SCRIPT_VERSION" \
  node <<'NODE'
const fs = require('fs');
const crypto = require('crypto');

const targetFile = process.env.TARGET_FILE;
const backupFile = process.env.BACKUP_FILE;
const metaFile = process.env.META_FILE;
const marker = process.env.PATCH_MARKER;
const scriptVersion = process.env.SCRIPT_VERSION;

const target = fs.readFileSync(targetFile, 'utf8');
const backup = fs.readFileSync(backupFile, 'utf8');

function sha256(content) {
  return crypto.createHash('sha256').update(content).digest('hex');
}

if (!target.includes(marker)) {
  process.stderr.write('Verification failed: patched bundle does not contain the marker.\n');
  process.exit(5);
}

const meta = {
  scriptVersion,
  patchMarker: marker,
  targetFile,
  backupFile,
  createdAt: new Date().toISOString(),
  sourceSha256: sha256(backup),
  patchedSha256: sha256(target),
};

fs.writeFileSync(metaFile, JSON.stringify(meta, null, 2));
NODE
}

restore_patch() {
  local target_file="$1"
  local backup_file="$2"
  local meta_file="$3"

  [[ -f "$backup_file" ]] || error "Backup file not found: $backup_file"
  cp -p "$backup_file" "$target_file"
  rm -f "$meta_file"
}

main() {
  need_cmd node
  need_cmd cp
  need_cmd mktemp

  local command=""
  if [[ $# -eq 0 ]]; then
    command="install"
  elif [[ "${1:-}" == "install" || "${1:-}" == "restore" || "${1:-}" == "status" || "${1:-}" == "help" || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    command="$1"
    shift || true
  elif [[ "${1:-}" == --* ]]; then
    command="install"
  else
    error "Unknown command: $1"
  fi

  local force="false"
  local target_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        [[ $# -ge 2 ]] || error "--file requires a path"
        target_file="$2"
        shift 2
        ;;
      --force)
        force="true"
        shift
        ;;
      help | install | restore | status)
        error "Unexpected extra command: $1"
        ;;
      *)
        error "Unknown option: $1"
        ;;
    esac
  done

  local platform
  platform="$(detect_platform)"

  if [[ -z "$target_file" ]]; then
    target_file="$(detect_default_target "$platform")"
  fi

  local backup_file
  local meta_file
  backup_file="$(bundle_backup_path "$target_file")"
  meta_file="$(bundle_meta_path "$target_file")"

  case "$command" in
    install)
      [[ -f "$target_file" ]] || error "Target file not found: $target_file"

      if [[ "$force" != "true" ]] && is_lingma_running "$platform"; then
        error "Lingma appears to be running. Quit Lingma first, or rerun with --force."
      fi

      if grep -Fq "$PATCH_MARKER" "$target_file"; then
        log "Already patched: $target_file"
        node_status "$target_file" "$backup_file" "$meta_file"
        return 0
      fi

      if [[ ! -f "$backup_file" ]]; then
        cp -p "$target_file" "$backup_file"
      fi

      local tmp_file
      tmp_file="$(mktemp "${TMPDIR:-/tmp}/lingma-auto-resume.XXXXXX")"
      trap 'rm -f "$tmp_file"' EXIT

      install_patch "$target_file" "$backup_file" "$meta_file" "$tmp_file"

      rm -f "$tmp_file"
      trap - EXIT

      log "Patched successfully: $target_file"
      node_status "$target_file" "$backup_file" "$meta_file"
      ;;
    restore)
      [[ -f "$target_file" ]] || error "Target file not found: $target_file"

      if [[ "$force" != "true" ]] && is_lingma_running "$platform"; then
        error "Lingma appears to be running. Quit Lingma first, or rerun with --force."
      fi

      restore_patch "$target_file" "$backup_file" "$meta_file"
      log "Restored successfully: $target_file"
      node_status "$target_file" "$backup_file" "$meta_file"
      ;;
    status)
      node_status "$target_file" "$backup_file" "$meta_file"
      ;;
    help | --help | -h)
      usage
      ;;
    *)
      error "Unknown command: $command"
      ;;
  esac
}

main "$@"
