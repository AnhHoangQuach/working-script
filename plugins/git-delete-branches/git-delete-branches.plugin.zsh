# ${0:A:h} = thư mục chứa plugin này (đã resolve symlink về repo)

## Xóa tất cả branch trừ main, develop, staging (gdelbr -h để xem option)
alias gdelbr="${0:A:h}/delete-branches.sh"
