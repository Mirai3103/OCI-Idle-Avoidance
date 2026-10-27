#!/bin/bash
#
# Gỡ cài đặt OCI-Idle-Avoidance khỏi VM.
#
# Script này đảo ngược đúng những gì bước cài đặt đã làm:
#   1. Dừng service và tắt tự chạy khi boot
#   2. Xoá file unit systemd
#   3. Xoá thư mục chứa script /opt/oci-idle-avoidance
#   4. (Tuỳ chọn) gỡ gói sysstat, chỉ khi truyền --remove-sysstat
#
# Cách dùng:
#   ./uninstall-oci-idle-avoidance.sh                   # gỡ service, giữ sysstat
#   ./uninstall-oci-idle-avoidance.sh --remove-sysstat  # gỡ luôn sysstat
#
# Chạy lại nhiều lần vẫn an toàn: bước nào đã gỡ rồi thì bỏ qua.

# Dừng ngay nếu một lệnh lỗi, hoặc dùng biến chưa khai báo
set -eu

# Tên service và đường dẫn, phải khớp với lúc cài
SERVICE=oci-idle-avoidance
UNIT_FILE=/etc/systemd/system/$SERVICE.service
INSTALL_DIR=/opt/oci-idle-avoidance

# Mặc định giữ sysstat vì có thể chương trình khác cũng đang dùng mpstat/iostat
REMOVE_SYSSTAT=false

# Đọc tham số dòng lệnh
for arg in "$@"; do
    case $arg in
        --remove-sysstat) REMOVE_SYSSTAT=true ;;
        -h|--help)
            echo "Cách dùng: $0 [--remove-sysstat]"
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

# 1. Dừng service và tắt tự chạy khi boot.
#    Khi service dừng, systemd kill luôn toàn bộ process con
#    (các load_generator.py), nên không còn tải CPU nào sót lại.
if systemctl cat "$SERVICE.service" &> /dev/null; then
    echo "Đang dừng và disable $SERVICE..."
    systemctl disable --now "$SERVICE"
else
    echo "Service $SERVICE không tồn tại, bỏ qua."
fi

# 2. Xoá file unit rồi báo systemd đọc lại cấu hình,
#    để service biến mất khỏi danh sách của systemctl.
if [[ -f $UNIT_FILE ]]; then
    echo "Đang xoá $UNIT_FILE..."
    rm -f "$UNIT_FILE"
    systemctl daemon-reload
    # Xoá trạng thái "failed" cũ nếu có, cho systemctl status sạch sẽ
    systemctl reset-failed "$SERVICE" 2> /dev/null || true
fi

# 3. Xoá thư mục chứa load_controller.sh, load_generator.py và mem_holder.py
if [[ -d $INSTALL_DIR ]]; then
    echo "Đang xoá $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
fi

# Phòng trường hợp ai đó từng chạy tay script ngoài systemd
# (ví dụ trong screen): kill mọi process còn sót chạy từ thư mục cài đặt,
# gồm controller, load generator (ăn CPU) và memory holder (giữ RAM).
if pkill -f "$INSTALL_DIR/"; then
    echo "Đã dừng các process còn sót lại."
fi

# 4. Chỉ gỡ sysstat khi được yêu cầu rõ ràng
if $REMOVE_SYSSTAT; then
    echo "Đang gỡ sysstat..."
    DEBIAN_FRONTEND=noninteractive apt-get remove -y sysstat
fi

echo "Đã gỡ xong OCI-Idle-Avoidance."
echo "Lưu ý: không còn gì giữ CPU trên 20%, VM có thể bị Oracle coi là idle sau 7 ngày."
