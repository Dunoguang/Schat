#!/system/bin/sh

# ============================================
# Schat 系统核心函数库
# 版本: 5.0 - 重构版（无awk，无adb disconnect，使用完整路径）
# ============================================

# 防止重复加载
if [ -n "$_SCHAT_CORE_LOADED" ]; then
    return 0 2>/dev/null || exit 0
fi
_SCHAT_CORE_LOADED=1

# 加载配置
if [ -f "/data/local/tmp/schat/config.sh" ]; then
    . /data/local/tmp/schat/config.sh
else
    echo "错误: 找不到 config.sh"
    exit 1
fi

# ==================== 基础工具函数 ====================

log_msg() {
    local script_name="${SCRIPT_NAME:-unknown}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$script_name] $1"
}

get_timestamp_ms() {
    local sec=$(date +%s)
    local ms=$(printf "%03d" $((RANDOM % 1000)))
    echo "${sec}${ms}"
}

init_std_dirs() {
    for dir in "$LOG_DIR" "$MATCH_DIR" "$NAME_DIR" "$PROCESSED_DIR" "$WATCHDOG_DIR" "$LOGS_DIR"; do
        mkdir -p "$dir" 2>/dev/null
    done
}

init_sdcard_dirs() {
    mkdir -p "$SDCARD_DIR" 2>/dev/null
}

# ==================== 进程管理函数 ====================

check_single_instance() {
    local script_num="${SCRIPT_NUM:-0}"
    local pid_file="${WATCHDOG_DIR}/${script_num}.pid"
    
    if [ -f "$pid_file" ]; then
        local old_pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            log_msg "错误: 已在运行 (PID: $old_pid)，退出"
            exit 1
        fi
    fi
    echo "$$" > "$pid_file"
}

update_heartbeat() {
    local script_num="${SCRIPT_NUM:-0}"
    echo $(date +%s) > "${WATCHDOG_DIR}/${script_num}.heartbeat"
}

check_heartbeat() {
    local script_num=$1
    local heartbeat_file="${WATCHDOG_DIR}/${script_num}.heartbeat"
    
    [ ! -f "$heartbeat_file" ] && return 1
    
    local last=$(cat "$heartbeat_file" 2>/dev/null)
    local now=$(date +%s)
    local diff=$((now - last))
    
    [ $diff -gt $HEARTBEAT_TIMEOUT ] && return 1
    return 0
}

restart_script() {
    local script_num=$1
    local script="${BASE_DIR}/${script_num}.sh"
    
    [ -f "$STOP_FLAG" ] && return
    [ -f "$script" ] && /system/bin/sh "$script" > /dev/null 2>&1 &
}

check_stop() {
    if [ -f "$STOP_FLAG" ]; then
        log_msg "检测到停止标志，退出"
        return 0
    fi
    return 1
}

cleanup_self() {
    local script_num="${SCRIPT_NUM:-0}"
    rm -f "${WATCHDOG_DIR}/${script_num}.pid"
    rm -f "${WATCHDOG_DIR}/${script_num}.heartbeat"
}

maintain_scripts() {
    local exclude_num=$1
    [ -f "$STOP_FLAG" ] && return
    
    for num in 1 2 3; do
        [ "$num" = "$exclude_num" ] && continue
        if ! check_heartbeat $num; then
            log_msg "⚠ ${num}.sh 心跳异常，尝试重启..."
            restart_script $num
        fi
    done
}

wait_with_stop_check() {
    local sleep_sec=${1:-$LOOP_SLEEP}
    local count=0
    while [ $count -lt $sleep_sec ]; do
        [ -f "$STOP_FLAG" ] && return 1
        sleep 1
        count=$((count + 1))
    done
    return 0
}

# ==================== 用户处理函数 ====================

clean_name() {
    printf "%s" "$1" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

validate_username() {
    local username="$1"
    
    [ -z "$username" ] && return 1
    [ ${#username} -gt 100 ] && return 1
    
    if echo "$username" | grep -q '[\\/:*?"<>|]'; then
        return 1
    fi
    return 0
}

check_user_in_list() {
    local username="$1"
    local user_list="$2"
    
    [ ! -f "$user_list" ] || [ ! -s "$user_list" ] && return 1
    
    local clean_user=$(clean_name "$username")
    while IFS= read -r line; do
        [ "$(clean_name "$line")" = "$clean_user" ] && return 0
    done < "$user_list"
    return 1
}

get_current_user() {
    local user=$(cat "$USER_NOW" 2>/dev/null | head -1)
    [ -n "$user" ] && echo "$user" || return 1
}

create_user_dir() {
    local username="$1"
    local user_dir="${SDCARD_DIR}/${username}"
    
    if mkdir -p "$user_dir" 2>/dev/null; then
        log_msg "已创建文件夹: $user_dir"
        return 0
    else
        log_msg "创建文件夹失败: $user_dir"
        return 1
    fi
}

check_user_exists() {
    local username="$1"
    [ ! -f "$USER_LIST" ] && return 1
    grep -x -F "$username" "$USER_LIST" > /dev/null 2>&1
}

add_user_to_list() {
    local username="$1"
    local user_list_dir=$(dirname "$USER_LIST")
    
    mkdir -p "$user_list_dir"
    
    if check_user_exists "$username"; then
        log_msg "用户已存在于列表中: $username"
        return 0
    fi
    
    if [ -f "$USER_LIST" ] && [ -s "$USER_LIST" ]; then
        tail -c1 "$USER_LIST" | read -r _ || echo "" >> "$USER_LIST"
        printf "%s\n" "$username" >> "$USER_LIST"
    else
        printf "%s\n" "$username" > "$USER_LIST"
    fi
    
    return $?
}

# ==================== 名字提取函数（无awk） ====================

extract_name() {
    local file="$1"
    local name=""
    
    # 方法1: 提取 name = 后到空格
    name=$(sed -n 's/.*name[[:space:]]*=[[:space:]]*\([^ ]*\).*/\1/p' "$file" 2>/dev/null | head -1)
    
    # 方法2: 提取到行尾，取第一个字段
    if [ -z "$name" ]; then
        name=$(sed -n 's/.*name[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$file" 2>/dev/null | head -1)
        name=$(echo "$name" | cut -d' ' -f1)
    fi
    
    # 方法3: grep 提取
    if [ -z "$name" ]; then
        name=$(grep -o 'name = [^ ]*' "$file" 2>/dev/null | head -1 | sed 's/name = //')
    fi
    
    # 清理
    name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 验证
    if [ -n "$name" ] && [ "$name" != "null" ] && [ "$name" != "undefined" ]; then
        if ! echo "$name" | grep -qE '^[0-9]{2}-[0-9]{2}'; then
            echo "$name"
        fi
    fi
}

# ==================== 日志处理函数 ====================

process_log() {
    local log_file="$1"
    local name=$(extract_name "$log_file")
    
    if [ -n "$name" ]; then
        local name_file="${NAME_DIR}/name_$(date +'%Y%m%d_%H%M%S_%N').txt"
        printf "%s\n" "$name" > "$name_file"
        log_msg "✓ 提取名字: '$name'"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $name" >> "${NAME_DIR}/all_names.txt"
    else
        log_msg "✗ 未找到有效名字: $(basename "$log_file")"
    fi
    
    mv "$log_file" "${PROCESSED_DIR}/" 2>/dev/null || rm -f "$log_file"
}

# ==================== 活动检测函数 ====================

is_target_activity() {
    local target="$1"
    [ -z "$target" ] && return 1
    
    local current_info=""
    current_info=$(dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp')
    
    if [ -z "$current_info" ]; then
        current_info=$(dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|mTopResumedActivity')
    fi
    
    if [ -z "$current_info" ]; then
        current_info=$(dumpsys activity top 2>/dev/null | grep -m1 'ACTIVITY' | head -1)
    fi
    
    if echo "$current_info" | grep -qi "$target"; then
        log_msg "✓ 匹配成功: 当前活动包含 $target"
        return 0
    else
        local current_activity=$(echo "$current_info" | head -1 | grep -oE '[a-zA-Z][a-zA-Z0-9_.]*/[a-zA-Z][a-zA-Z0-9_.]*' | head -1)
        [ -n "$current_activity" ] && log_msg "当前活动: $current_activity"
        return 1
    fi
}

# ==================== 名字匹配处理函数 ====================

process_name() {
    local name_file="$1"
    local raw=$(cat "$name_file" 2>/dev/null | head -1)
    local name=$(clean_name "$raw")
    
    [ -z "$name" ] && { rm -f "$name_file"; return; }
    
    log_msg "处理名字: $name"
    
    if check_user_in_list "$name" "$USER_LIST"; then
        log_msg "✓ 匹配成功: $name"
        
        if is_target_activity "$TARGET_ACTIVITY"; then
            log_msg "当前活动是 $TARGET_ACTIVITY，启动 4.sh"
            [ -f "${BASE_DIR}/4.sh" ] && /system/bin/sh "${BASE_DIR}/4.sh" "$name" &
        else
            log_msg "当前活动不是 $TARGET_ACTIVITY，跳过启动"
        fi
    else
        log_msg "✗ 匹配失败: $name"
        echo "$(date '+%Y-%m-%d %H:%M:%S')|$name" >> "$FAILED_LOG"
    fi
    
    rm -f "$name_file"
}

# ==================== 设备IP查询函数（纯shell，无awk） ====================

get_class_ip() {
    local class_name="$1"
    [ -z "$class_name" ] && return 1
    
    while IFS=: read -r cls ip port; do
        if [ "$cls" = "$class_name" ]; then
            echo "${ip}:${port}"
            return 0
        fi
    done < "$DEVICES_FILE"
    return 1
}

get_all_classes() {
    while IFS=: read -r cls ip port; do
        [ -n "$cls" ] && echo "$cls"
    done < "$DEVICES_FILE"
}

get_all_ips() {
    while IFS=: read -r cls ip port; do
        [ -n "$ip" ] && echo "${ip}:${port}"
    done < "$DEVICES_FILE"
}

list_all_classes() { get_all_classes; }
get_ip_by_class() { get_class_ip "$1"; }
list_all_ips_with_port() { get_all_ips; }

# ==================== ADB远程执行函数（使用完整路径，不断开连接） ====================

remote_exec_timeout() {
    local ip="$1"
    local cmd="$2"
    local timeout_sec=${3:-$REMOTE_TIMEOUT}
    
    $ADB_SCRIPT connect "$ip" >/dev/null 2>&1
    sleep 0.5
    
    local device_serial=""
    device_serial=$($ADB_SCRIPT devices | grep "${ip}" | grep "device" | head -1 | sed 's/[[:space:]].*//')
    [ -z "$device_serial" ] && device_serial="$ip"
    
    local result=""
    local ret=0
    
    if command -v timeout >/dev/null 2>&1; then
        result=$(timeout "$timeout_sec" $ADB_SCRIPT -s "$device_serial" shell "$cmd" 2>&1)
        ret=$?
    else
        result=$($ADB_SCRIPT -s "$device_serial" shell "$cmd" 2>&1)
        ret=$?
    fi
    
    if [ $ret -eq 0 ]; then
        [ -n "$result" ] && echo "$result"
        return 0
    fi
    return 1
}

test_remote_connection() {
    local ip="$1"
    $ADB_SCRIPT connect "$ip" >/dev/null 2>&1
    local test_result=$($ADB_SCRIPT -s "$ip" shell "echo ok" 2>&1)
    echo "$test_result" | grep -q "ok"
}

# ==================== 消息处理函数 ====================

build_message() {
    echo "${1}:${2}:${3}"
}

get_message_size() {
    echo -n "$1" | wc -c
}

is_message_too_large() {
    [ $(get_message_size "$1") -gt 1048576 ]
}

save_message_local() {
    local sender="$1"
    local class="$2"
    local receiver="$3"
    local message="$4"
    
    local timestamp=$(get_timestamp_ms)
    local target_dir="${SDCARD_DIR}/${sender}/${class}/${receiver}"
    
    mkdir -p "$target_dir" 2>/dev/null
    [ ! -d "$target_dir" ] && return 1
    
    echo "$message" > "${target_dir}/${timestamp}.txt"
    [ -f "${target_dir}/${timestamp}.txt" ] && echo "$timestamp" || return 1
}

save_message_remote() {
    local remote_addr="$1"
    local receiver="$2"
    local class="$3"
    local sender="$4"
    local message="$5"
    
    local escaped_message=$(echo "$message" | sed 's/"/\\"/g' | sed "s/'/\\'/g")
    local remote_cmd="$SAVE_MSG_SCRIPT \"$receiver\" \"$class\" \"$sender\" \"$escaped_message\""
    
    remote_exec_timeout "$remote_addr" "$remote_cmd" "$REMOTE_TIMEOUT"
}

send_message() {
    local sender="$1"
    local class="$2"
    local receiver="$3"
    local msg_type="$4"
    local msg_body="$5"
    local remote_addr="$6"
    
    local full_message=$(build_message "$sender" "$msg_type" "$msg_body")
    
    log_msg "=========================================="
    log_msg "开始发送消息: $sender -> $receiver"
    log_msg "消息大小: $(get_message_size "$full_message") 字节"
    log_msg "=========================================="
    
    is_message_too_large "$full_message" && { log_msg "消息过大"; return 1; }
    
    log_msg ">>> [1/2] 本地保存"
    local local_timestamp=$(save_message_local "$sender" "$class" "$receiver" "$full_message")
    [ -z "$local_timestamp" ] && { log_msg "本地保存失败"; return 2; }
    log_msg "✓ 本地保存成功"
    
    log_msg ">>> [2/2] 远程保存"
    local remote_success=false
    for retry in 1 2; do
        log_msg "远程尝试 $retry/2"
        if save_message_remote "$remote_addr" "$receiver" "$class" "$sender" "$full_message"; then
            remote_success=true
            break
        fi
        sleep 1
    done
    
    if [ "$remote_success" = true ]; then
        log_msg "✓ 消息发送完成"
        return 0
    else
        log_msg "远程保存失败，回滚删除本地消息"
        delete_local_message "$sender" "$class" "$receiver" "$local_timestamp"
        return 3
    fi
}

save_received_message() {
    local user1="$1"
    local class="$2"
    local user2="$3"
    local msg_content="$4"
    
    local target_dir="${SDCARD_DIR}/${user1}/${class}/${user2}"
    local timestamp=$(get_timestamp_ms)
    
    mkdir -p "$target_dir" 2>/dev/null
    [ ! -d "$target_dir" ] && { echo "无法创建目录"; return 1; }
    
    echo "$msg_content" > "${target_dir}/${timestamp}.txt"
    [ -f "${target_dir}/${timestamp}.txt" ] && echo "✓ 已保存" || { echo "写入失败"; return 1; }
}

delete_local_message() {
    local user1="$1"
    local class="$2"
    local user2="$3"
    local timestamp="$4"
    
    local file_path="${SDCARD_DIR}/${user1}/${class}/${user2}/${timestamp}.txt"
    [ -f "$file_path" ] && rm -f "$file_path" && log_msg "已删除: $file_path"
}

get_message_dir() {
    echo "${SDCARD_DIR}/${1}/${2}/${3}"
}

# ==================== 数据库函数 ====================

backup_database() {
    local src="/data/data/com.czhl.pass/databases/czhl.db"
    local dst="/sdcard/schat/czhl.db"
    
    if [ -f "$src" ]; then
        mkdir -p /sdcard/schat 2>/dev/null
        cp "$src" "$dst" 2>/dev/null && log_msg "数据库备份成功" || log_msg "数据库备份失败"
    else
        log_msg "源数据库不存在"
    fi
}

restore_database() {
    local src="/sdcard/schat/czhl.db"
    local dst="/data/data/com.czhl.pass/databases/czhl.db"
    
    if [ -f "$src" ]; then
        mkdir -p /data/data/com.czhl.pass/databases 2>/dev/null
        cp "$src" "$dst" 2>/dev/null && log_msg "数据库恢复成功" || log_msg "数据库恢复失败"
    else
        log_msg "备份文件不存在"
    fi
}

# ==================== 应用管理函数 ====================

disable_app() {
    local pkg="$1"
    pm list packages | grep -q "$pkg" || { log_msg "应用不存在: $pkg"; return 1; }
    pm disable "$pkg" 2>/dev/null && log_msg "已禁用: $pkg" || log_msg "禁用失败: $pkg"
}

enable_app() {
    local pkg="$1"
    pm list packages | grep -q "$pkg" || { log_msg "应用不存在: $pkg"; return 1; }
    pm enable "$pkg" 2>/dev/null && log_msg "已启用: $pkg" || log_msg "启用失败: $pkg"
}

start_app() {
    local pkg="$1"
    pm list packages | grep -q "$pkg" || { log_msg "应用不存在: $pkg"; return 1; }
    
    local main_activity=$(cmd package resolve-activity --brief "$pkg" 2>/dev/null | tail -n 1)
    
    if [ -z "$main_activity" ] || [ "$main_activity" = "$pkg" ]; then
        main_activity=$(dumpsys package "$pkg" 2>/dev/null | grep -A 1 "android.intent.action.MAIN" | grep "$pkg/" | head -1 | sed 's/.*\([a-zA-Z][a-zA-Z0-9_.]*\/[a-zA-Z][a-zA-Z0-9_.]*\).*/\1/')
    fi
    
    if [ -n "$main_activity" ]; then
        am start -n "$main_activity" 2>/dev/null && { log_msg "已启动: $pkg"; return 0; }
    fi
    
    monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 2>/dev/null && log_msg "已启动: $pkg (monkey)" || log_msg "启动失败: $pkg"
}

force_stop_app() {
    local pkg="$1"
    local pids=$(pgrep -f "$pkg" 2>/dev/null)
    for pid in $pids; do kill -9 "$pid" 2>/dev/null; done
    am force-stop "$pkg" 2>/dev/null
    log_msg "已强制停止: $pkg"
}

kill_and_restore() {
    local pkg="$1"
    local times=${2:-5}
    
    for i in $(seq 1 $times); do
        log_msg "========== 第 $i 次操作 =========="
        force_stop_app "$pkg"
        restore_database
        [ $i -lt $times ] && sleep 1
    done
}

# ==================== 头像查询函数 ====================

get_avatar_url_from_db() {
    local name="$1"
    [ -z "$name" ] && return 1
    
    local line=$(grep -a "$name" "$DB_PATH" 2>/dev/null | head -1)
    [ -z "$line" ] && return 1
    
    local before=$(echo "$line" | sed "s/${name}.*//")
    local pos=$((${#before} + 1))
    
    local part
    if [ $pos -gt 104 ]; then
        local start=$((pos - 104))
        part=$(echo "$line" | cut -c${start}-$((pos - 1)))
    else
        part=$(echo "$line" | cut -c1-$((pos - 1)))
    fi
    
    local url=$(echo "$part" | grep -o 'https://[^[:space:]]*' | head -1)
    [ -n "$url" ] && echo "$url" && return 0
    return 1
}

get_avatar_urls_from_db() {
    local query="$1"
    [ -z "$query" ] && return 1
    
    if echo "$query" | grep -q '|'; then
        local oldIFS="$IFS"
        IFS='|'
        for name in $query; do
            name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -z "$name" ] && continue
            if url=$(get_avatar_url_from_db "$name"); then
                echo "${name}:${url}"
            else
                echo "${name}:"
            fi
        done
        IFS="$oldIFS"
    else
        get_avatar_url_from_db "$query"
    fi
}

get_remote_avatar_urls() {
    local remote_addr="$1"
    local query="$2"
    [ -z "$remote_addr" ] && return 1
    [ -z "$query" ] && return 1
    
    $ADB_SCRIPT connect "$remote_addr" >/dev/null 2>&1
    sleep 0.3
    
    local device_serial=$($ADB_SCRIPT devices | grep "${remote_addr}" | grep "device" | head -1 | sed 's/[[:space:]].*//')
    [ -z "$device_serial" ] && device_serial="$remote_addr"
    
    $ADB_SCRIPT -s "$device_serial" shell "sh /data/local/tmp/schat/16.sh \"$query\"" 2>/dev/null
}

# ==================== 同步函数 ====================

get_remote_user_list() {
    local ip="$1"
    $ADB_SCRIPT connect "$ip" >/dev/null 2>&1
    sleep 0.3
    $ADB_SCRIPT -s "$ip" shell cat /sdcard/schat/USER 2>/dev/null
}

sync_user_list_to_all() {
    local main_ip="$1"
    
    [ ! -f "$USER_LIST" ] && { log_msg "USER列表不存在"; return 1; }
    
    [ -z "$main_ip" ] && [ -f "$MAIN_IP_FILE" ] && main_ip=$(cat "$MAIN_IP_FILE" 2>/dev/null)
    [ -z "$main_ip" ] && return 1
    
    log_msg "开始同步USER列表（跳过主IP: $main_ip）"
    
    local all_ips=$(get_all_ips)
    [ -z "$all_ips" ] && return 1
    
    echo "$all_ips" | while read ip; do
        [ -z "$ip" ] && continue
        [ "$ip" = "$main_ip" ] && { log_msg "跳过主IP: $ip"; continue; }
        
        log_msg "同步到: $ip"
        $ADB_SCRIPT connect "$ip" 2>/dev/null 1>/dev/null
        if $ADB_SCRIPT -s "$ip" push "$USER_LIST" /sdcard/schat/USER 2>/dev/null; then
            log_msg "✓ 同步成功: $ip"
        else
            log_msg "✗ 同步失败: $ip"
        fi
    done
}

# ==================== 清理函数 ====================

clean_script_logs() {
    rm -rf "${LOGS_DIR}"/* 2>/dev/null
    rm -rf "${NAME_DIR}"/* 2>/dev/null
    rm -rf "${PROCESSED_DIR}"/* 2>/dev/null
    rm -f "${MATCH_DIR}/.last_match_time" 2>/dev/null
    log_msg "已清理脚本日志"
}

clean_chat_records() {
    find "$SDCARD_DIR" -type f -name "*.txt" -delete 2>/dev/null
    log_msg "已删除所有聊天记录"
}

daily_cleanup() {
    local today=$(date +%Y%m%d)
    
    if [ "$(cat "$FIRSTTIME_FILE" 2>/dev/null)" != "$today" ]; then
        log_msg "每日首次运行，执行清理任务"
        clean_script_logs
        
        local current_week=$((today / 7))
        if [ "$(cat "$LAST_CLEAN_WEEK_FILE" 2>/dev/null)" != "$current_week" ]; then
            clean_chat_records
            echo "$current_week" > "$LAST_CLEAN_WEEK_FILE"
        fi
        echo "$today" > "$FIRSTTIME_FILE"
    fi
}

# ==================== ADB连接函数（使用完整路径） ====================

connect_remote_device() {
    local ip="$1"
    local timeout_sec=${2:-10}
    
    log_msg "目标IP: $ip"
    
    while true; do
        log_msg "正在执行: $ADB_SCRIPT connect $ip"
        
        if command -v timeout >/dev/null 2>&1; then
            $ADB_SCRIPT connect "$ip" &
            local pid=$!
            for i in $(seq 1 $timeout_sec); do
                sleep 1
                if ! kill -0 $pid 2>/dev/null; then
                    wait $pid
                    [ $? -eq 0 ] && { log_msg "连接成功！"; return 0; }
                    break
                fi
            done
            kill -9 $pid 2>/dev/null
            wait $pid 2>/dev/null
        else
            $ADB_SCRIPT connect "$ip" &
            local pid=$!
            sleep $timeout_sec
            if kill -0 $pid 2>/dev/null; then
                kill -9 $pid 2>/dev/null
                wait $pid 2>/dev/null
            else
                wait $pid
                [ $? -eq 0 ] && { log_msg "连接成功！"; return 0; }
            fi
        fi
        
        log_msg "连接失败，1秒后重试..."
        sleep 1
    done
}

# ==================== 停止脚本函数 ====================

stop_all_scripts() {
    log_msg "=========================================="
    log_msg "开始停止所有 Schat 脚本"
    log_msg "=========================================="
    
    log_msg "[1/5] 写入停止标志"
    mkdir -p "$(dirname "$STOP_FLAG")" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$STOP_FLAG"
    log_msg "✓ 停止标志已创建"
    
    log_msg "等待1.5秒让脚本自清理..."
    sleep 1.5
    
    log_msg "[2/5] 终止脚本进程"
    for num in 1 2 3; do
        local pid_file="${WATCHDOG_DIR}/${num}.pid"
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file" 2>/dev/null)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                log_msg "终止脚本 ${num}.sh (PID: $pid)"
                kill -9 "$pid" 2>/dev/null
            fi
        fi
    done
    
    log_msg "[3/5] 清理看门狗文件"
    for num in 1 2 3; do
        rm -f "${WATCHDOG_DIR}/${num}.pid" 2>/dev/null
        rm -f "${WATCHDOG_DIR}/${num}.heartbeat" 2>/dev/null
    done
    
    log_msg "[4/5] 清理残留日志"
    rm -f "${NAME_DIR}/name_*.txt" 2>/dev/null
    rm -f "${PROCESSED_DIR}"/*.txt 2>/dev/null
    rm -f "${MATCH_DIR}/.last_match_time" 2>/dev/null
    
    log_msg "[5/5] 删除停止标志"
    rm -f "$STOP_FLAG" 2>/dev/null
    
    log_msg "=========================================="
    log_msg "停止完成"
    log_msg "=========================================="
}

# ==================== 脚本主函数 ====================

script_1_main() {
    init_std_dirs
    check_single_instance
    log_msg "日志监控脚本启动 (目标: $TARGET_KEYWORD)"
    
    local last_match=0
    while ! check_stop; do
        update_heartbeat
        maintain_scripts $SCRIPT_NUM
        
        local logs=$(logcat -d | tail -200)
        
        if echo "$logs" | grep -q "$TARGET_KEYWORD"; then
            local now=$(date +%s)
            [ -f "${MATCH_DIR}/.last_match_time" ] && last_match=$(cat "${MATCH_DIR}/.last_match_time" 2>/dev/null || echo 0)
            
            if [ $((now - last_match)) -gt $MATCH_COOLDOWN ]; then
                echo "$now" > "${MATCH_DIR}/.last_match_time"
                local log_file="${LOG_DIR}/log_$(date +'%Y%m%d_%H%M%S').txt"
                {
                    echo "检测时间: $(date '+%Y-%m-%d %H:%M:%S')"
                    echo "$logs" | grep "$TARGET_KEYWORD" | head -20
                } > "$log_file"
                log_msg "✓ 捕获目标日志: $log_file"
                backup_database
            fi
        fi
        
        wait_with_stop_check || break
    done
    cleanup_self
}

script_2_main() {
    init_std_dirs
    check_single_instance
    log_msg "日志处理脚本启动"
    
    while ! check_stop; do
        update_heartbeat
        maintain_scripts $SCRIPT_NUM
        
        find "$LOG_DIR" -maxdepth 1 -name "log_*.txt" 2>/dev/null | while read f; do
            [ -f "$f" ] && process_log "$f"
        done
        
        wait_with_stop_check || break
    done
    cleanup_self
}

script_3_main() {
    init_std_dirs
    check_single_instance
    log_msg "名字匹配脚本启动"
    
    # 启动 13.sh（后台运行，执行每日清理和 ADB 连接）
    if [ -f "${BASE_DIR}/13.sh" ]; then
        log_msg "启动 13.sh（后台）"
        /system/bin/sh "${BASE_DIR}/13.sh" &
    else
        log_msg "警告: 13.sh 不存在"
    fi
    
    log_msg "=========================================="
    log_msg "初始化完成，进入业务匹配"
    log_msg "=========================================="
    
    while ! check_stop; do
        update_heartbeat
        maintain_scripts $SCRIPT_NUM
        
        find "$NAME_DIR" -maxdepth 1 -name "name_*.txt" 2>/dev/null | while read f; do
            [ -n "$f" ] && process_name "$f"
        done
        
        wait_with_stop_check || break
    done
    cleanup_self
}

script_4_main() {
    local USER_NAME="$1"
    [ -z "$USER_NAME" ] && { log_msg "错误: 未接收到用户名参数"; exit 1; }
    echo "$USER_NAME" > "$USER_NOW"
    log_msg "已写入当前用户: $USER_NAME"
    disable_app "$TARGET_PACKAGE_DISABLE"
    start_app "$TARGET_PACKAGE_START"
    exit 0
}

script_5_main() {
    enable_app "$TARGET_PACKAGE_DISABLE"
    sleep 1
    kill_and_restore "$TARGET_PACKAGE_DISABLE" 5
    sleep 1
    start_app "$TARGET_PACKAGE_DISABLE"
    exit 0
}

script_6_main() {
    local USERNAME="$1"
    [ -z "$USERNAME" ] && { echo "用法: $0 <用户名>"; exit 1; }
    local clean_user=$(clean_name "$USERNAME")
    validate_username "$clean_user" || exit 1
    create_user_dir "$clean_user"
    add_user_to_list "$clean_user"
    exit 0
}

script_7_main() {
    [ $# -ne 3 ] && { echo "用法: $0 <用户名1> <班级> <用户名2>"; exit 1; }
    local target_dir="${SDCARD_DIR}/$1/$2/$3"
    if [ -d "$target_dir" ]; then
        echo "目录已存在: $target_dir"
        exit 0
    fi
    if mkdir -p "$target_dir" 2>/dev/null; then
        chmod 755 "$target_dir" 2>/dev/null
        echo "创建成功: $target_dir"
        exit 0
    else
        echo "创建失败: $target_dir"
        exit 1
    fi
}

script_8_main() {
    [ $# -ne 4 ] && { echo "用法: $0 <用户名1> <班级> <用户名2> <IP:端口>"; exit 1; }
    "${BASE_DIR}/7.sh" "$1" "$2" "$3" || exit 1
    remote_exec_timeout "$4" "${BASE_DIR}/7.sh \"$3\" \"$2\" \"$1\"" 10
    exit 0
}

script_9_main() {
    [ $# -ne 4 ] && { echo "用法: $0 <用户名1> <班级> <用户名2> <消息内容>"; exit 1; }
    save_received_message "$1" "$2" "$3" "$4"
    exit $?
}

script_10_main() {
    [ $# -ne 6 ] && { echo "用法: $0 <发言人> <班级> <接收人> <消息类型> <消息内容> <IP:端口>"; exit 1; }
    send_message "$1" "$2" "$3" "$4" "$5" "$6"
    exit $?
}

script_11_main() {
    [ ! -f "$DEVICES_FILE" ] && exit 1
    case "$1" in
        0) list_all_classes ;;
        1) get_ip_by_class "$2" ;;
        2) list_all_ips_with_port ;;
        *) exit 1 ;;
    esac
}

script_12_main() {
    [ $# -ne 1 ] && exit 1
    get_remote_user_list "$1"
}

script_13_main() {
    daily_cleanup
    [ ! -f "$MAIN_IP_FILE" ] && { log_msg "错误: 找不到IP文件"; exit 1; }
    local IP=$(cat "$MAIN_IP_FILE" | tr -d '[:space:]')
    [ -z "$IP" ] && { log_msg "错误: IP为空"; exit 1; }
    connect_remote_device "$IP"
}

script_14_main() {
    sync_user_list_to_all "$(cat "$MAIN_IP_FILE" 2>/dev/null)"
}

script_15_main() {
    init_std_dirs
    stop_all_scripts
}

script_16_main() {
    [ $# -eq 0 ] && { echo "用法: $0 <姓名> 或 <姓名1>|<姓名2>|..."; exit 1; }
    get_avatar_urls_from_db "$1"
    exit $?
}

script_17_main() {
    [ $# -ne 2 ] && { echo "用法: $0 <IP:端口> <用户名或批量用户>"; exit 1; }
    get_remote_avatar_urls "$1" "$2"
}

# ==================== 入口调度 ====================

dispatch_script() {
    local script_name="${SCRIPT_NAME:-unknown}"
    local script_num="${SCRIPT_NUM:-${script_name%.sh}}"
    
    case "$script_num" in
        1) script_1_main "$@" ;;
        2) script_2_main "$@" ;;
        3) script_3_main "$@" ;;
        4) script_4_main "$@" ;;
        5) script_5_main "$@" ;;
        6) script_6_main "$@" ;;
        7) script_7_main "$@" ;;
        8) script_8_main "$@" ;;
        9) script_9_main "$@" ;;
        10) script_10_main "$@" ;;
        11) script_11_main "$@" ;;
        12) script_12_main "$@" ;;
        13) script_13_main "$@" ;;
        14) script_14_main "$@" ;;
        15) script_15_main "$@" ;;
        16) script_16_main "$@" ;;
        17) script_17_main "$@" ;;
        *) log_msg "未知脚本: $script_name"; exit 1 ;;
    esac
}

# 由各脚本显式调用 dispatch_script，不自动执行