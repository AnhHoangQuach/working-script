# Liệt kê các command tự viết trong repo working-script.
#
# Quy ước để command hiện mô tả: đặt comment "## <mô tả>" ngay trên dòng
#   alias <tên>=...    hoặc    <tên>() {
# trong file plugins/<plugin>/<plugin>.plugin.zsh.

# Thư mục plugins/ của repo (${0:A} đã resolve symlink từ $ZSH_CUSTOM về repo)
typeset -g _WS_PLUGINS_DIR=${0:A:h:h}

## Liệt kê các command tự viết đang có
ws-help() {
  local file line desc name status_note

  for file in $_WS_PLUGINS_DIR/*/*.plugin.zsh(N); do
    print -P "%B${file:h:t}%b"
    desc=
    while IFS= read -r line; do
      name=
      if [[ $line == '## '* ]]; then
        desc=${line#'## '}
        continue
      elif [[ $line =~ '^alias ([A-Za-z0-9_.-]+)=' ]]; then
        name=$match[1]
      elif [[ $line =~ '^(function +)?([A-Za-z0-9_.-]+) *\(\)' ]]; then
        name=$match[2]
      fi

      if [[ -n $name && $name != _* ]]; then
        status_note=
        (( $+aliases[$name] || $+functions[$name] )) || status_note=' (chưa bật, chạy ./install.sh)'
        printf '  %-14s %s%s\n' "$name" "${desc:--}" "$status_note"
      fi
      [[ $line == '#'* || -z $line ]] || desc=
    done < "$file"
  done
}
