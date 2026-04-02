#!/usr/bin/env bash

# =============================================================================
# Generate RELEASE_NOTES.md from commit subjects between tags
# (태그 범위의 commit subject를 기반으로 RELEASE_NOTES.md 생성)
#
# Input:
#   - TAG_NAME environment variable
#
# Output:
#   - RELEASE_NOTES.md
#
# Supported commit subject formats:
#   - [type] Subject
#   - type: Subject
# =============================================================================

set -euo pipefail

# =============================================================================
# 1) Validate input tag
# (입력 태그 검증)
# =============================================================================
if [[ -z "${TAG_NAME:-}" ]]; then
  echo "[ERROR] TAG_NAME is not set."
  exit 1
fi

# =============================================================================
# 2) Resolve comparison range
# (비교 범위 계산)
# - Find previous tag before current tag
# - If not found, treat as initial release
# =============================================================================
PREV_TAG="$(git describe --tags --abbrev=0 "${TAG_NAME}^" 2>/dev/null || true)"

if [[ -n "${PREV_TAG}" ]]; then
  RANGE="${PREV_TAG}..${TAG_NAME}"
else
  RANGE="${TAG_NAME}"
fi

# =============================================================================
# 3) Collect commit subjects
# (commit subject 수집)
# =============================================================================
COMMITS="$(git log ${RANGE} --pretty=format:'%s')"

# =============================================================================
# 4) Initialize temp files
# (카테고리별 임시 파일 초기화)
# - mktemp으로 임시 디렉토리를 만들어 작업 디렉토리 오염 방지
# - trap으로 스크립트 종료 시 자동 정리
# =============================================================================
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

: > "${TMP_DIR}/features.txt"
: > "${TMP_DIR}/fixes.txt"
: > "${TMP_DIR}/perf.txt"
: > "${TMP_DIR}/build.txt"
: > "${TMP_DIR}/design.txt"
: > "${TMP_DIR}/style.txt"
: > "${TMP_DIR}/refactor.txt"
: > "${TMP_DIR}/cleanup.txt"
: > "${TMP_DIR}/comment.txt"
: > "${TMP_DIR}/docs.txt"
: > "${TMP_DIR}/tests.txt"
: > "${TMP_DIR}/chores.txt"
: > "${TMP_DIR}/rename.txt"
: > "${TMP_DIR}/remove.txt"
: > "${TMP_DIR}/setting.txt"
: > "${TMP_DIR}/breaking.txt"
: > "${TMP_DIR}/hotfix.txt"
: > "${TMP_DIR}/merge.txt"
: > "${TMP_DIR}/others.txt"

# =============================================================================
# 5) Normalize and classify commit subjects
# (commit subject 정규화 및 분류)
# =============================================================================
while IFS= read -r line; do
  [[ -z "${line}" ]] && continue

  TYPE="others"
  SUBJECT="${line}"

  # Format 1: [type] Subject ([type] 형식)
  if [[ "${line}" =~ ^\[([^\]]+)\][[:space:]]+(.+)$ ]]; then
    TYPE="${BASH_REMATCH[1]}"
    SUBJECT="${BASH_REMATCH[2]}"

  # Format 2: type: Subject (type: 형식)
  elif [[ "${line}" =~ ^([^:]+):[[:space:]]+(.+)$ ]]; then
    TYPE="${BASH_REMATCH[1]}"
    SUBJECT="${BASH_REMATCH[2]}"
  fi

  # Normalize type text (type 문자열 정규화)
  # - 앞뒤 공백 제거 (bash 내장)
  # - 소문자 변환 (bash 4.0+, GitHub Actions runner 호환)
  TYPE="${TYPE#"${TYPE%%[![:space:]]*}"}"
  TYPE="${TYPE%"${TYPE##*[![:space:]]}"}"
  TYPE="${TYPE,,}"

  case "${TYPE}" in
    feature|feat) echo "- ${SUBJECT}" >> "${TMP_DIR}/features.txt" ;;
    fix) echo "- ${SUBJECT}" >> "${TMP_DIR}/fixes.txt" ;;
    perf) echo "- ${SUBJECT}" >> "${TMP_DIR}/perf.txt" ;;
    build) echo "- ${SUBJECT}" >> "${TMP_DIR}/build.txt" ;;
    design) echo "- ${SUBJECT}" >> "${TMP_DIR}/design.txt" ;;
    style) echo "- ${SUBJECT}" >> "${TMP_DIR}/style.txt" ;;
    refactor) echo "- ${SUBJECT}" >> "${TMP_DIR}/refactor.txt" ;;
    cleanup) echo "- ${SUBJECT}" >> "${TMP_DIR}/cleanup.txt" ;;
    comment) echo "- ${SUBJECT}" >> "${TMP_DIR}/comment.txt" ;;
    docs|doc) echo "- ${SUBJECT}" >> "${TMP_DIR}/docs.txt" ;;
    test|tests) echo "- ${SUBJECT}" >> "${TMP_DIR}/tests.txt" ;;
    chore) echo "- ${SUBJECT}" >> "${TMP_DIR}/chores.txt" ;;
    rename) echo "- ${SUBJECT}" >> "${TMP_DIR}/rename.txt" ;;
    remove) echo "- ${SUBJECT}" >> "${TMP_DIR}/remove.txt" ;;
    setting|settings) echo "- ${SUBJECT}" >> "${TMP_DIR}/setting.txt" ;;
    "!breaking change"|breaking) echo "- ${SUBJECT}" >> "${TMP_DIR}/breaking.txt" ;;
    "!hotfix"|hotfix) echo "- ${SUBJECT}" >> "${TMP_DIR}/hotfix.txt" ;;
    merge) echo "- ${SUBJECT}" >> "${TMP_DIR}/merge.txt" ;;
    *) echo "- ${SUBJECT}" >> "${TMP_DIR}/others.txt" ;;
  esac
done <<< "${COMMITS}"

# =============================================================================
# 6) Build RELEASE_NOTES.md
# (간결한 공개용 릴리즈 노트 생성)
# - Expose only major sections
# - Group perf/refactor/cleanup into Improvements
# - Hide internal/noisy sections from public release notes
# =============================================================================
{
  if [[ -n "${PREV_TAG}" ]]; then
    echo "Changes since \`${PREV_TAG}\`."
  else
    echo "Initial release."
  fi
  echo

  # --- Breaking ---
  if [[ -s "${TMP_DIR}/breaking.txt" ]]; then
    echo "## Breaking Changes"
    sort -u "${TMP_DIR}/breaking.txt"
    echo
  fi

  # --- Hotfix ---
  if [[ -s "${TMP_DIR}/hotfix.txt" ]]; then
    echo "## Hotfix"
    sort -u "${TMP_DIR}/hotfix.txt"
    echo
  fi

  # --- Features ---
  if [[ -s "${TMP_DIR}/features.txt" ]]; then
    echo "## Features"
    sort -u "${TMP_DIR}/features.txt"
    echo
  fi

  # --- Fixes ---
  if [[ -s "${TMP_DIR}/fixes.txt" ]]; then
    echo "## Fixes"
    sort -u "${TMP_DIR}/fixes.txt"
    echo
  fi

  # --- Improvements (perf + refactor + cleanup 통합) ---
  if [[ -s "${TMP_DIR}/perf.txt" || -s "${TMP_DIR}/refactor.txt" || -s "${TMP_DIR}/cleanup.txt" ]]; then
    echo "## Improvements"
    cat "${TMP_DIR}/perf.txt" "${TMP_DIR}/refactor.txt" "${TMP_DIR}/cleanup.txt" 2>/dev/null | sort -u
    echo
  fi

  # --- Documentation ---
  if [[ -s "${TMP_DIR}/docs.txt" ]]; then
    echo "## Documentation"
    sort -u "${TMP_DIR}/docs.txt"
    echo
  fi

  # --- Fallback: 공개 섹션이 하나도 없을 때 ---
  if [[ ! -s "${TMP_DIR}/breaking.txt" && ! -s "${TMP_DIR}/hotfix.txt" && \
        ! -s "${TMP_DIR}/features.txt" && ! -s "${TMP_DIR}/fixes.txt" && \
        ! -s "${TMP_DIR}/perf.txt" && ! -s "${TMP_DIR}/refactor.txt" && \
        ! -s "${TMP_DIR}/cleanup.txt" && ! -s "${TMP_DIR}/docs.txt" ]]; then
    echo "No user-facing changes in this release."
    echo
  fi

  if [[ -n "${PREV_TAG}" ]]; then
    echo "---"
    echo "**Full Changelog**: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/compare/${PREV_TAG}...${TAG_NAME}"
  fi
} > RELEASE_NOTES.md

# =============================================================================
# 7) Print generated notes
# (생성 결과 로그 출력)
# =============================================================================
OTHERS_COUNT="$(wc -l < "${TMP_DIR}/others.txt")"
if [[ "${OTHERS_COUNT}" -gt 0 ]]; then
  echo "[INFO] ${OTHERS_COUNT} commit(s) not classified (others)."
fi

echo "========== RELEASE_NOTES.md =========="
cat RELEASE_NOTES.md
echo "====================================="