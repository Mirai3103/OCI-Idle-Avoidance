#!/bin/bash
#
# Gỡ cài đặt OCI-Idle-Avoidance khỏi VM.
#
# Script này đảo ngược đúng những gì install.sh đã làm:
#   1. Dừng service và tắt tự chạy khi boot
#   2. Xoá file unit systemd
#   3. Xoá thư mục chứa script /opt/oci-idle-avoidance
#   4. Dừng các process còn sót nếu từng chạy tay ngoài systemd
#   5. Xoá bản uninstall ~/uninstall-oci-idle-avoidance.sh mà install.sh tạo ra
#   6. (Tuỳ chọn) gỡ gói sysstat, chỉ khi truyền --remove-sysstat
#
# Cách dùng (từ thư mục repo, hoặc bản copy trong home):
#   ./uninstall.sh                     # gỡ service, giữ sysstat
#   ./uninstall.sh --remove-sysstat    # gỡ luôn sysstat
#   ~/uninstall-oci-idle-avoidance.sh  # như trên, khi đã xoá repo
#
# Chạy lại nhiều lần vẫn an toàn: bước nào đã gỡ rồi thì bỏ qua.

# Dừng ngay nếu một lệnh lỗi, hoặc dùng biến chưa khai báo
set -eu

# Tên service và đường dẫn, phải khớp với install.sh
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
#    (load generator và memory holder), nên không còn tải CPU/RAM nào sót lại.
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

# 4. Phòng trường hợp ai đó từng chạy tay script ngoài systemd
#    (ví dụ trong screen): kill các process còn sót.
#    Regex khớp chính xác dòng lệnh của từng loại process, để không kill
#    nhầm thứ khác chỉ nhắc tới đường dẫn (ví dụ: vim, less, một shell ssh).
#    - Controller trước: nó tự dọn các process con khi nhận SIGTERM
#    - Rồi load generator (ăn CPU) và memory holder (giữ RAM) còn mồ côi
CONTROLLER_RE="^(/usr)?/bin/bash (.*/)?load_controller\.sh$"
WORKER_RE="^python3 $INSTALL_DIR/(load_generator|mem_holder)\.py "
STRAY=false
if pkill -f "$CONTROLLER_RE"; then
    STRAY=true
    # Controller chỉ xử lý SIGTERM sau khi lần đo mpstat hiện tại xong
    # (tối đa INTERVAL = 10 giây), nên đợi tới 15 giây cho nó tự thoát.
    for ((i = 0; i < 15; i++)); do
        pgrep -f "$CONTROLLER_RE" > /dev/null || break
        sleep 1
    done
    # Quá thời gian mà vẫn còn thì buộc dừng
    pkill -KILL -f "$CONTROLLER_RE" || true
fi
pkill -f "$WORKER_RE" && STRAY=true
if $STRAY; then
    echo "Đã dừng các process còn sót lại."
fi

# 5. Xoá bản uninstall mà install.sh đặt trong home của người gọi sudo.
#    Nếu đang chạy chính bản đó thì vẫn xoá được: bash đã mở sẵn file,
#    nên phần còn lại của script vẫn chạy tiếp bình thường.
TARGET_USER=${SUDO_USER:-root}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
UNINSTALLER="$TARGET_HOME/uninstall-$SERVICE.sh"
if [[ -f $UNINSTALLER ]]; then
    echo "Đang xoá $UNINSTALLER..."
    rm -f "$UNINSTALLER"
fi

# 6. Chỉ gỡ sysstat khi được yêu cầu rõ ràng,
#    bằng trình quản lý gói của distro (apt, dnf hoặc yum)
if $REMOVE_SYSSTAT; then
    echo "Đang gỡ sysstat..."
    if command -v apt-get &> /dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq sysstat
    elif command -v dnf &> /dev/null; then
        dnf remove -y -q sysstat
    elif command -v yum &> /dev/null; then
        yum remove -y -q sysstat
    else
        echo "Không biết gỡ sysstat trên distro này, hãy gỡ tay." >&2
    fi
fi

echo "Đã gỡ xong OCI-Idle-Avoidance."
echo "Lưu ý: không còn gì giữ CPU và RAM trên 20%, VM có thể bị Oracle coi là idle sau 7 ngày."
