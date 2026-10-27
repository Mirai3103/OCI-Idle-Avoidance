#!/bin/bash
#
# Cài đặt OCI-Idle-Avoidance lên VM.
#
# Script này:
#   1. Cài các gói cần thiết (sysstat cho mpstat, python3) nếu còn thiếu
#   2. Copy các script chạy thật vào /opt/oci-idle-avoidance
#   3. Cài unit systemd, bật tự chạy khi boot và (khởi động lại) service
#   4. Đặt một bản uninstall vào ~/uninstall-oci-idle-avoidance.sh, để gỡ được
#      kể cả khi đã xoá thư mục repo
#
# Cách dùng (từ thư mục repo vừa clone):
#   ./install.sh
#
# Chạy lại để cập nhật sau khi git pull hoặc sửa ngưỡng trong
# scripts/load_controller.sh: file được ghi đè và service được khởi động lại.

# Dừng ngay nếu một lệnh lỗi, hoặc dùng biến chưa khai báo
set -eu

# Tên service và đường dẫn, phải khớp với uninstall.sh
SERVICE=oci-idle-avoidance
UNIT_FILE=/etc/systemd/system/$SERVICE.service
INSTALL_DIR=/opt/oci-idle-avoidance

# Thư mục chứa install.sh, tức thư mục repo, để chạy được từ bất kỳ đâu
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Đọc tham số dòng lệnh
for arg in "$@"; do
    case $arg in
        -h|--help)
            echo "Cách dùng: $0"
            exit 0
            ;;
        *)
            echo "Tham số không hợp lệ: $arg (xem --help)" >&2
            exit 1
            ;;
    esac
done

# Các bước dưới đây đều cần quyền root. Nếu chưa phải root thì
# tự chạy lại chính script này qua sudo, giữ nguyên tham số.
if (( EUID != 0 )); then
    exec sudo "$0" "$@"
fi

# Service chạy bằng systemd, không có systemd thì không cài được
if ! command -v systemctl &> /dev/null; then
    echo "Không tìm thấy systemd, script này chỉ hỗ trợ VM dùng systemd." >&2
    exit 1
fi

# 1. Cài gói còn thiếu bằng trình quản lý gói của distro:
#    apt cho Ubuntu/Debian, dnf/yum cho Oracle Linux.
#    $1 = lệnh cần có, $2 = tên gói cung cấp lệnh đó
function require {
    command -v "$1" &> /dev/null && return
    echo "Đang cài $2 (cần cho $1)..."
    if command -v apt-get &> /dev/null; then
        # Image cloud mới tạo thường chưa có danh sách gói, nên update trước
        DEBIAN_FRONTEND=noninteractive apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$2"
    elif command -v dnf &> /dev/null; then
        dnf install -y -q "$2"
    elif command -v yum &> /dev/null; then
        yum install -y -q "$2"
    else
        echo "Không biết cài $2 trên distro này, hãy cài tay rồi chạy lại." >&2
        exit 1
    fi
}

require mpstat sysstat
require python3 python3

# 2. Copy các script chạy thật. Controller cần quyền chạy (755),
#    hai file Python chỉ cần đọc (644) vì được gọi qua python3.
echo "Đang cài script vào $INSTALL_DIR..."
install -d "$INSTALL_DIR"
install -m 755 "$REPO_DIR/scripts/load_controller.sh" "$INSTALL_DIR/"
install -m 644 "$REPO_DIR/scripts/load_generator.py" "$INSTALL_DIR/"
install -m 644 "$REPO_DIR/scripts/mem_holder.py" "$INSTALL_DIR/"

# 3. Cài unit systemd, báo systemd đọc lại cấu hình, bật tự chạy khi boot.
#    Dùng restart thay vì start để lần cài lại cũng nạp script mới.
echo "Đang cài và khởi động service $SERVICE..."
install -m 644 "$REPO_DIR/scripts/$SERVICE.service" "$UNIT_FILE"
systemctl daemon-reload
systemctl enable "$SERVICE"
systemctl restart "$SERVICE"

# 4. Đặt bản uninstall vào home của người gọi sudo (hoặc root nếu
#    chạy thẳng bằng root), chủ sở hữu và group là của người đó.
TARGET_USER=${SUDO_USER:-root}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
UNINSTALLER="$TARGET_HOME/uninstall-$SERVICE.sh"
install -m 755 -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" \
    "$REPO_DIR/uninstall.sh" "$UNINSTALLER"

echo
echo "Đã cài xong. Service đang: $(systemctl is-active "$SERVICE")"
echo "  Xem log:   journalctl -u $SERVICE -f"
echo "  Trạng thái: systemctl status $SERVICE"
echo "  Gỡ cài đặt: $UNINSTALLER"
