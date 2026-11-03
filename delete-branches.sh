#!/usr/bin/env bash
#
# Xóa tất cả branch trừ các branch được bảo vệ (mặc định: main, develop, staging).
#
# Usage:
#   ./delete-branches.sh [options]
#
# Options:
#   -r, --remote        Xóa cả branch trên remote (mặc định chỉ xóa local)
#   -o, --origin NAME   Tên remote (mặc định: origin)
#   -f, --force         Xóa cả branch chưa merge (git branch -D)
#   -n, --dry-run       Chỉ liệt kê, không xóa
#   -y, --yes           Bỏ qua bước xác nhận
#   -h, --help          Hiển thị hướng dẫn
#
# Thêm branch cần giữ lại qua biến môi trường:
#   PROTECTED_BRANCHES="main develop staging release" ./delete-branches.sh
#
# Cài đặt vào oh-my-zsh (dùng lệnh `gdelbr` ở mọi repo):
#   1. Tạo custom plugin:
#        PLUGIN_DIR=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/git-delete-branches
#        mkdir -p "$PLUGIN_DIR"
#        cp delete-branches.sh "$PLUGIN_DIR/" && chmod +x "$PLUGIN_DIR/delete-branches.sh"
#        echo 'alias gdelbr="${0:A:h}/delete-branches.sh"' > "$PLUGIN_DIR/git-delete-branches.plugin.zsh"
#      (Dùng `ln -sf "$PWD/delete-branches.sh" "$PLUGIN_DIR/"` thay cho `cp` nếu muốn
#       alias luôn chạy bản mới nhất của file này.)
#   2. Bật plugin trong ~/.zshrc:
#        plugins=(git git-delete-branches)
#   3. Nạp lại shell:
#        exec zsh
#   4. Dùng thử:
#        gdelbr -n
#
# Lưu ý WSL: nếu gặp lỗi "compinit: no such file or directory: .../_docker" thì
# Docker Desktop đang tắt khiến symlink completion bị gãy. Mở Docker Desktop, hoặc:
#   sudo rm /usr/share/zsh/vendor-completions/_docker && rm -f ~/.zcompdump* && exec zsh

set -euo pipefail

PROTECTED_BRANCHES=${PROTECTED_BRANCHES:-"main develop staging"}
REMOTE_NAME="origin"
DELETE_REMOTE=false
FORCE=false
DRY_RUN=false
ASSUME_YES=false

usage() {
  sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--remote)  DELETE_REMOTE=true ;;
    -o|--origin)  REMOTE_NAME="${2:?Thiếu tên remote}"; shift ;;
    -f|--force)   FORCE=true ;;
    -n|--dry-run) DRY_RUN=true ;;
    -y|--yes)     ASSUME_YES=true ;;
    -h|--help)    usage 0 ;;
    *) echo "Option không hợp lệ: $1" >&2; usage 1 ;;
  esac
  shift
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Lỗi: thư mục hiện tại không phải git repository." >&2
  exit 1
}

is_protected() {
  local branch=$1 p
  for p in $PROTECTED_BRANCHES; do
    [[ "$branch" == "$p" ]] && return 0
  done
  return 1
}

current_branch=$(git symbolic-ref --quiet --short HEAD || true)

# --- Thu thập branch local ---
local_targets=()
while IFS= read -r branch; do
  is_protected "$branch" && continue
  if [[ "$branch" == "$current_branch" ]]; then
    echo "Bỏ qua '$branch' vì đang checkout. Hãy chuyển sang main/develop/staging trước." >&2
    continue
  fi
  local_targets+=("$branch")
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

# --- Thu thập branch remote ---
remote_targets=()
if $DELETE_REMOTE; then
  git remote get-url "$REMOTE_NAME" >/dev/null 2>&1 || {
    echo "Lỗi: remote '$REMOTE_NAME' không tồn tại." >&2
    exit 1
  }
  git fetch "$REMOTE_NAME" --prune --quiet
  while IFS= read -r ref; do
    branch=${ref#"$REMOTE_NAME/"}
    [[ "$branch" == "HEAD" || "$ref" == "$REMOTE_NAME" ]] && continue
    is_protected "$branch" && continue
    remote_targets+=("$branch")
  done < <(git for-each-ref --format='%(refname:short)' "refs/remotes/$REMOTE_NAME/")
fi

# --- Hiển thị ---
if [[ ${#local_targets[@]} -eq 0 && ${#remote_targets[@]} -eq 0 ]]; then
  echo "Không có branch nào cần xóa. (Giữ lại: $PROTECTED_BRANCHES)"
  exit 0
fi

echo "Branch được giữ lại: $PROTECTED_BRANCHES"
if [[ ${#local_targets[@]} -gt 0 ]]; then
  echo
  echo "Local branch sẽ bị xóa (${#local_targets[@]}):"
  printf '  - %s\n' "${local_targets[@]}"
fi
if [[ ${#remote_targets[@]} -gt 0 ]]; then
  echo
  echo "Remote branch trên '$REMOTE_NAME' sẽ bị xóa (${#remote_targets[@]}):"
  printf '  - %s\n' "${remote_targets[@]}"
fi

if $DRY_RUN; then
  echo
  echo "[dry-run] Không có branch nào bị xóa."
  exit 0
fi

if ! $ASSUME_YES; then
  echo
  read -r -p "Xác nhận xóa? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Đã hủy."; exit 0; }
fi

# --- Xóa ---
failed=0
delete_flag=$($FORCE && echo "-D" || echo "-d")

for branch in "${local_targets[@]}"; do
  if git branch "$delete_flag" "$branch" >/dev/null 2>&1; then
    echo "✔ Đã xóa local: $branch"
  else
    echo "✘ Không xóa được local: $branch (chưa merge? dùng --force)" >&2
    failed=$((failed + 1))
  fi
done

for branch in "${remote_targets[@]}"; do
  if git push "$REMOTE_NAME" --delete "$branch" >/dev/null 2>&1; then
    echo "✔ Đã xóa remote: $REMOTE_NAME/$branch"
  else
    echo "✘ Không xóa được remote: $REMOTE_NAME/$branch" >&2
    failed=$((failed + 1))
  fi
done

if [[ $failed -gt 0 ]]; then
  echo
  echo "Hoàn tất với $failed lỗi." >&2
  exit 1
fi

echo
echo "Hoàn tất."
