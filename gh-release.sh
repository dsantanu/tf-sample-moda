#!/usr/bin/env bash
# ==========================================================
# gh-release-cli.sh — Automated GitHub release helper
# Name   : Github Release CLI
# Author : Santanu Das (@dsantanu)  |  License: MIT
# Version: v2.0.0
# Desc   : Extract metadata, enforce version bump, prepend
#          CHANGELOG, create tag and GitHub release (via gh)
# ==========================================================
set -euo pipefail

# --- CLI args ---------------------------------------------
TARGET_FILE='header-info.txt'
CHANGELOG='CHANGELOG.md'
ADD_ALL=false
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -f, --file <path>    File to find the release info
                       (default: header-info.txt)
  -m, --message <msg>  Commit message
                       (default: "Release <version>")
  -a, --add-all        Add file(s) contents to index
                       (performs: git add -A)
  -d, --dry-run        Show what would be done
                       (without changing anything)
  -h, --help           Show this help and exit
EOF
}

# --- Parse args -------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file) TARGET_FILE="$2"; shift 2 ;;
    -m|--message) USER_COMMIT_MSG="$2"; shift 2 ;;
    -a|--add-all) ADD_ALL=true; shift ;;
    -d|--dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# --- Determine file ---------------------------------------
if [[ -s "${TARGET_FILE}" ]]; then
  TARGET_FILE="${TARGET_FILE}"
else
  TARGET_FILE=$(\
      ls *.sh *.py *.go *.tf 2>/dev/null | head -n1 || true\
  )
fi

[[ -z "${TARGET_FILE}" ]] && { echo "❌ No file specified or found."; exit 1; }
[[ ! -f "${TARGET_FILE}" ]] && { echo "❌ Target file not found: ${TARGET_FILE}"; exit 1; }

echo "📄 Target file: ${TARGET_FILE}"

# --- Extract optional metadata ----------------------------
NAME=$(awk -F':' '/^# Name/ {print $2}' "${TARGET_FILE}" | xargs || true)
AUTHOR=$(awk -F':' '/^# Author/ {print $2}' "${TARGET_FILE}" | xargs || true)
VERSION=$(awk -F':' '/^# Version/ {print $2}' "${TARGET_FILE}" | xargs || true)

# --- Handle version ---------------------------------------
if [[ -z "${VERSION}" ]]; then
  read -rp "Enter version (format vX.Y.Z): " VERSION
fi

SEMVER_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+$'
if ! [[ "${VERSION}" =~ ${SEMVER_REGEX} ]]; then
  echo "⛔ Invalid version format: '${VERSION}'"
  echo "   Expected: vMAJOR.MINOR.PATCH (e.g., v1.0.0)"
  exit 1
fi

LATEST_TAG=$(git tag --sort=-v:refname | head -n1 || true)

# --- Detect file changes ----------------------------------
FILE_CHANGED=false
git diff --name-only -- "$TARGET_FILE" | grep -q "^${TARGET_FILE}$" && FILE_CHANGED=true
git diff --cached --name-only -- "$TARGET_FILE" | grep -q "^${TARGET_FILE}$" && FILE_CHANGED=true

if [[ "${FILE_CHANGED}" == true && "${VERSION}" == "${LATEST_TAG}" ]]; then
  echo "⛔ Detected changes in ${TARGET_FILE} but version header is still '${VERSION}'."
  echo "   Please bump the version before releasing."
  exit 1
fi

# --- Ask for messages -------------------------------------
DEFAULT_COMMIT_MSG="Release ${VERSION}"
read -rp "Enter commit message [${DEFAULT_COMMIT_MSG}]: " USER_COMMIT_MSG
COMMIT_MSG="${USER_COMMIT_MSG:-$DEFAULT_COMMIT_MSG}"

DEFAULT_TAG_MSG="${NAME:-Project} ${VERSION}"
read -rp "Enter tag message [${DEFAULT_TAG_MSG}]: " USER_TAG_MSG
TAG_MSG="${USER_TAG_MSG:-$DEFAULT_TAG_MSG}"

# --- Preview ----------------------------------------------
echo
echo "🧾 Version : ${VERSION}"
echo "💬 Commit  : ${COMMIT_MSG}"
echo "🏷️ Tag Msg : ${TAG_MSG}"
echo "📁 File    : ${TARGET_FILE}"
if [[ "${DRY_RUN}" == true ]]; then
  echo "Dry Run    : ${DRY_RUN}"
  echo
  echo "💡 Dry run only — no git actions performed."
  exit 0
fi
read -rp "Proceed with release? [y/N]: " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "❎ Aborted."; exit 0; }

# --- Update CHANGELOG -------------------------------------
DATE_STR=$(date +"%Y-%m-%d")
if [[ -f "${CHANGELOG}" ]]; then
  TMP="$(mktemp)"
  HEADER_END_LINE=$(grep -nE '^---|^## ' "${CHANGELOG}" | head -n1 | cut -d: -f1)
  if [[ -n "${HEADER_END_LINE}" ]]; then
    head -n "${HEADER_END_LINE}" "${CHANGELOG}" > "${TMP}"
    echo "" >> "${TMP}"
    echo "## ${VERSION} — ${DATE_STR}" >> "${TMP}"
    echo "- ${COMMIT_MSG}" >> "${TMP}"
    echo "" >> "${TMP}"
    tail -n +"$((HEADER_END_LINE + 1))" "${CHANGELOG}" >> "${TMP}"
  else
    echo "## ${VERSION} — ${DATE_STR}" > "${TMP}"
    echo "- ${COMMIT_MSG}" >> "${TMP}"
    echo "" >> "${TMP}"
    cat "${CHANGELOG}" >> "${TMP}"
  fi
  mv "${TMP}" "${CHANGELOG}"
else
  {
    echo "# Changelog"
    echo ""
    echo "All notable changes will be documented in this file."
    echo ""
    echo "---"
    echo ""
    echo "## ${VERSION} — ${DATE_STR}"
    echo "- ${COMMIT_MSG}"
    echo ""
  } > "${CHANGELOG}"
fi

# --- Git commit, tag, push --------------------------------
#git add "${TARGET_FILE}" "${CHANGELOG}"
[[ ${ADD_ALL} == 'true' ]] && git add -A || true
git commit -m "${COMMIT_MSG}" . || true
git tag -a "${VERSION}" -m "${TAG_MSG}"
git push origin HEAD
git push origin "${VERSION}"

# --- GitHub release (if gh exists) ------------------------
if command -v gh >/dev/null 2>&1; then
  echo "📡 Creating GitHub release..."
  gh release create "${VERSION}" "${TARGET_FILE}" \
    --title "${NAME:-$(basename "$(pwd)")} ${VERSION}" \
    --notes-file "${CHANGELOG}"
  echo "✅ GitHub release published."
else
  echo "⚠️  GitHub CLI (gh) not found — tag created but release skipped."
fi

echo
echo "🎉 Done! Tagged ${VERSION}, updated CHANGELOG, and pushed to origin."
