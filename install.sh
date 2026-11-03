#!/usr/bin/env bash
#
# Cài tất cả plugin trong thư mục plugins/ vào oh-my-zsh.
#
# Usage:
#   ./install.sh
#
# Script sẽ:
#   1. Symlink từng plugins/<tên>/ vào $ZSH_CUSTOM/plugins/<tên>
#      (symlink nên chỉ cần `git pull` là plugin được cập nhật)
#   2. Thêm <tên> vào dòng plugins=(...) trong ~/.zshrc (backup ~/.zshrc trước khi sửa)
# Chạy lại nhiều lần vẫn an toàn: plugin đã cài sẽ được bỏ qua.
#
# Thêm plugin mới: tạo thư mục plugins/<tên>/ chứa file <tên>.plugin.zsh, rồi chạy lại script.
#
# Hỗ trợ: macOS (bash 3.2 mặc định, BSD tools) và Ubuntu/WSL (GNU tools).
#
# Yêu cầu: zsh và oh-my-zsh.
#   macOS:  zsh có sẵn (mặc định từ Catalina)
#   Ubuntu: sudo apt install -y zsh
#   oh-my-zsh (cả hai):
#     sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
#
# Lưu ý WSL: nếu gặp lỗi "compinit: no such file or directory: .../_docker" thì
# Docker Desktop đang tắt khiến symlink completion bị gãy. Mở Docker Desktop, hoặc:
#   sudo rm /usr/share/zsh/vendor-completions/_docker && rm -f ~/.zcompdump* && exec zsh

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PLUGINS_SRC="$REPO_DIR/plugins"
ZSH_DIR=${ZSH:-$HOME/.oh-my-zsh}
ZSH_CUSTOM=${ZSH_CUSTOM:-$ZSH_DIR/custom}
ZSHRC=${ZSHRC:-$HOME/.zshrc}

case "$(uname -s)" in
  Darwin) ZSH_INSTALL_HINT="brew install zsh" ;;
  *)      ZSH_INSTALL_HINT="sudo apt install -y zsh" ;;
esac

command -v zsh >/dev/null 2>&1 || {
  echo "Lỗi: chưa cài zsh. Chạy: $ZSH_INSTALL_HINT" >&2
  exit 1
}
[[ -f "$ZSH_DIR/oh-my-zsh.sh" ]] || {
  echo "Lỗi: chưa cài oh-my-zsh tại $ZSH_DIR. Xem hướng dẫn ở đầu file install.sh." >&2
  exit 1
}
[[ -f "$ZSHRC" ]] && grep -q '^plugins=(' "$ZSHRC" || {
  echo "Lỗi: không tìm thấy dòng plugins=(...) trong $ZSHRC." >&2
  exit 1
}

# Đường dẫn thật của thư mục (thay cho `readlink -f`, không có trên macOS < 12.3)
real_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

# In ra danh sách plugin đang bật trong ~/.zshrc (hỗ trợ cả dạng 1 dòng và nhiều dòng)
enabled_plugins() {
  awk '/^plugins=\(/ { inblock = 1 } inblock { print } inblock && /\)/ { exit }' "$ZSHRC" |
    sed 's/#.*//; s/^plugins=(//; s/).*//' | tr -s ' \t' '\n' | sed '/^$/d'
}

# Chèn tên plugin vào trước dấu ")" đóng của khối plugins=(...)
enable_plugin() {
  local name=$1 tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/zshrc.XXXXXX")
  awk -v name="$name" '
    !done && /^plugins=\(/ { inblock = 1 }
    inblock && /\)/ {
      # Dạng nhiều dòng ")" đứng riêng: chèn 1 dòng mới; dạng 1 dòng: chèn trước ")"
      if ($0 ~ /^[[:space:]]*\)/) print "  " name
      else sub(/\)/, " " name ")")
      inblock = 0; done = 1
    }
    { print }
  ' "$ZSHRC" > "$tmp"
  # Ghi đè nội dung thay vì mv để giữ nguyên ~/.zshrc nếu nó là symlink (dotfiles)
  cat "$tmp" > "$ZSHRC"
  rm -f "$tmp"
}

mkdir -p "$ZSH_CUSTOM/plugins"
zshrc_backed_up=false
installed=()

for plugin_dir in "$PLUGINS_SRC"/*/; do
  [[ -d "$plugin_dir" ]] || continue
  name=$(basename "$plugin_dir")
  plugin_dir=${plugin_dir%/}
  target="$ZSH_CUSTOM/plugins/$name"

  if [[ ! -f "$plugin_dir/$name.plugin.zsh" ]]; then
    echo "⚠ Bỏ qua '$name': thiếu file $name.plugin.zsh" >&2
    continue
  fi

  # 1. Symlink plugin vào oh-my-zsh
  if [[ -L "$target" && "$(real_dir "$target")" == "$(real_dir "$plugin_dir")" ]]; then
    echo "✔ $name: đã link sẵn"
  else
    if [[ -e "$target" || -L "$target" ]]; then
      backup="$ZSH_CUSTOM/plugins/.$name.backup-$(date +%Y%m%d%H%M%S)"
      mv "$target" "$backup"
      echo "↻ $name: bản cài cũ được chuyển sang $backup"
    fi
    ln -s "$plugin_dir" "$target"
    echo "✔ $name: đã link $target -> $plugin_dir"
  fi

  # 2. Bật plugin trong ~/.zshrc
  if enabled_plugins | grep -qx "$name"; then
    echo "✔ $name: đã có trong plugins=(...)"
  else
    if ! $zshrc_backed_up; then
      cp "$ZSHRC" "$ZSHRC.backup-$(date +%Y%m%d%H%M%S)"
      zshrc_backed_up=true
    fi
    enable_plugin "$name"
    echo "✔ $name: đã thêm vào plugins=(...) trong $ZSHRC"
  fi

  installed+=("$name")
done

if [[ ${#installed[@]} -eq 0 ]]; then
  echo "Không tìm thấy plugin nào trong $PLUGINS_SRC." >&2
  exit 1
fi

echo
echo "Hoàn tất: ${installed[*]}"
echo "Chạy 'exec zsh' để nạp lại shell."
