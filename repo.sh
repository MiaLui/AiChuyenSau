#!/usr/bin/env bash
# Termux one-shot: ensure git, clone (skip if exists), cd vào repo, (tùy chọn) checkout branch, mở web, chạy ai.sh
# Usage: ./setup-aichuyensau.sh [branch] [dest-folder]
set -euo pipefail

REPO_URL="https://github.com/MiaLui/AiChuyenSau.git"
WEB_URL="https://ai.studio/apps/drive/1-eIAQJpWJrzTZvuDDigJoQ4H5sUbDDC_"
BRANCH="${1-}" 
DEST="${2-}" 

info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ OK ]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

open_web() {
  info "Đang mở Web..."
  if have termux-open-url; then
    termux-open-url "$WEB_URL" >/dev/null 2>&1 || true
  elif have xdg-open; then
    xdg-open "$WEB_URL" >/dev/null 2>&1 || true
  elif have am; then
    am start -a android.intent.action.VIEW -d "$WEB_URL" >/dev/null 2>&1 || true
  else
    warn "Không tìm thấy tiện ích mở URL tự động. Hãy mở thủ công: $WEB_URL"
  fi
}

open_web

if ! have git; then
  info "Đang cài git…"
  pkg update -y >/dev/null 2>&1 || true
  pkg install -y git >/dev/null 2>&1
  ok "Đã cài: $(git --version)"
else
  ok "Đã có git: $(git --version)"
fi

if [[ -z "${DEST}" ]]; then
  base="$(basename "${REPO_URL}")"
  DEST="${base%.git}"
fi

if [[ -d "${DEST}" ]]; then
  ok "Phát hiện thư mục '${DEST}'"
  if [[ -d "${DEST}/.git" && -n "${BRANCH}" ]]; then
    info "Đang đồng bộ '${BRANCH}'…"
    git -C "${DEST}" fetch --all --quiet || true
    if ! git -C "${DEST}" rev-parse --verify "${BRANCH}" >/dev/null 2>&1; then
      git -C "${DEST}" checkout -b "${BRANCH}" "origin/${BRANCH}" || git -C "${DEST}" checkout "${BRANCH}" || true
    else
      git -C "${DEST}" checkout "${BRANCH}" >/dev/null 2>&1 || true
    fi
    git -C "${DEST}" pull --ff-only || true
  fi
else
  info "Tạo mới ${DEST}"
  if [[ -n "${BRANCH}" ]]; then
    git clone --recursive -b "${BRANCH}" "${REPO_URL}" "${DEST}"
  else
    git clone --recursive "${REPO_URL}" "${DEST}"
  fi
  ok "Hoàn tất."
fi

cd "${DEST}"

if [[ ! -f "./ai.sh" ]]; then
  err "Không tìm thấy ai.sh trong $(pwd)."
  ls -la
  exit 1
fi

chmod +x ./ai.sh || true
info "Chạy ./ai.sh …"
if have bash; then
  exec bash ./ai.sh
else
  exec sh ./ai.sh
fi
