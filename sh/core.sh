#!/system/bin/sh

# ============================================
# Schat 系统共享配置文件（核心功能）
# 版本: 4.0
# ============================================

# 加载配置文件
SCRIPT_DIR_CONFIG="$(dirname "$0")"
if [ -f "${SCRIPT_DIR_CONFIG}/config.sh" ]; then
    . "${SCRIPT_DIR_CONFIG}/config.sh"
elif [ -f "/data/local/tmp/schat/config.sh" ]; then
    . "/data/local/tmp/schat/config.sh"
else
    echo "错误: 找不到 config.sh 配置文件"
    exit 1
fi

# ==================== 基础函数 ====================

# 日志输出（带脚本名）
log_msg() {
    local script_name="${SCRIPT_NAME:-unknown}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$script_name] $1"
}

# 获取毫秒时间戳
get_timestamp_ms() {
    local sec=$(date +%s)
    local ms=$(printf "%03d" $((RANDOM % 1000)))
    echo "${sec}${ms}"
}

# 初始化标准目录
init_std_dirs() {
    for dir in "$LOG_DIR" "$MATCH_DIR" "$NAME_DIR" "$PROCESSED_DIR" "$WATCHDOG_DIR" "$LOGS_DIR"; do
        mkdir -p "$dir" 2>/dev/null
    done
}

# 初始化SD卡目录
init_sdcard_dirs() {
    mkdir -p "$SDCARD_DIR" 2>/dev/null
}

# ==================== 进程管理函数 ====================

# 单实例检查
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

# 更新心跳
update_heartbeat() {
    local script_num="${SCRIPT_NUM:-0}"
    echo $(date +%s) > "${WATCHDOG_DIR}/${script_num}.heartbeat"
}

# 检查心跳
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

# 重启脚本
restart_script() {
    local script_num=$1
    local script="${BASE_DIR}/${script_num}.sh"
    
    [ -f "$STOP_FLAG" ] && return
    [ -f "$script" ] && /system/bin/sh "$script" > /dev/null 2>&1 &
}

# 检查停止标志
check_stop() {
    if [ -f "$STOP_FLAG" ]; then
        log_msg "检测到停止标志，退出"
        return 0
    fi
    return 1
}

# 清理当前脚本的PID和心跳
cleanup_self() {
    local script_num="${SCRIPT_NUM:-0}"
    rm -f "${WATCHDOG_DIR}/${script_num}.pid"
    rm -f "${WATCHDOG_DIR}/${script_num}.heartbeat"
}

# 维护其他脚本
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

# 等待并检查停止
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

# 清理用户名（去除空白、换行）
clean_name() {
    printf "%s" "$1" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# 验证用户名是否有效
validate_username() {
    local username="$1"
    
    if [ -z "$username" ]; then
        log_msg "错误: 用户名为空"
        return 1
    fi
    
    if [ ${#username} -gt 100 ]; then
        log_msg "错误: 用户名过长（超过100字符）"
        return 1
    fi
    
    if echo "$username" | grep -q '[\\/:*?"<>|]'; then
        log_msg "错误: 用户名包含非法字符"
        return 1
    fi
    
    return 0
}

# 检查用户是否在列表中
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

# 获取当前登录用户
get_current_user() {
    local user=$(cat "$USER_NOW" 2>/dev/null | head -1)
    [ -n "$user" ] && echo "$user" || return 1
}

# 创建用户目录
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

# 检查用户是否已存在
check_user_exists() {
    local username="$1"
    
    [ ! -f "$USER_LIST" ] && return 1
    grep -x -F "$username" "$USER_LIST" > /dev/null 2>&1
}

# 添加用户到列表
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
    
    if [ $? -eq 0 ]; then
        log_msg "已添加用户到列表: $username"
        return 0
    else
        log_msg "写入用户列表失败"
        return 1
    fi
}

# ==================== 名字提取函数 ====================

# 从日志文件提取名字（不使用awk）
extract_name_from_log() {
    local file="$1"
    local name=""
    
    # 方法1: 直接提取 name = 后面的内容
    name=$(sed -n 's/.*name[[:space:]]*=[[:space:]]*\([^ ]*\).*/\1/p' "$file" 2>/dev/null | head -1)
    
    # 方法2: 提取到行尾
    if [ -z "$name" ]; then
        name=$(sed -n 's/.*name[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$file" 2>/dev/null | head -1)
        name=$(echo "$name" | cut -d' ' -f1)
    fi
    
    # 方法3: 使用 grep 提取
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

# ==================== 设备IP查询函数（不使用awk）====================

# 获取班级IP
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

# 获取所有班级名
get_all_classes() {
    while IFS=: read -r cls ip port; do
        [ -n "$cls" ] && echo "$cls"
    done < "$DEVICES_FILE"
}

# 获取所有IP
get_all_ips() {
    while IFS=: read -r cls ip port; do
        [ -n "$ip" ] && echo "${ip}:${port}"
    done < "$DEVICES_FILE"
}

# 列出所有班级名
list_all_classes() {
    while IFS=: read -r cls ip port; do
        [ -n "$cls" ] && echo "$cls"
    done < "$DEVICES_FILE"
}

# 根据班级名查IP:端口
get_ip_by_class() {
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

# 列出所有IP:端口
list_all_ips_with_port() {
    while IFS=: read -r cls ip port; do
        [ -n "$ip" ] && echo "${ip}:${port}"
    done < "$DEVICES_FILE"
}

# ==================== 头像查询函数 ====================

# 从本地数据库中查询单个用户头像 URL
get_avatar_url_from_db() {
    local name="$1"
    [ -z "$name" ] && return 1

    local line
    line=$(grep -a "$name" "$DB_PATH" 2>/dev/null | head -1)
    [ -z "$line" ] && return 1

    local before
    before=$(echo "$line" | sed "s/${name}.*//")
    local pos=$((${#before} + 1))

    local part
    if [ $pos -gt 104 ]; then
        local start=$((pos - 104))
        part=$(echo "$line" | cut -c${start}-$((pos - 1)))
    else
        part=$(echo "$line" | cut -c1-$((pos - 1)))
    fi

    local url
    url=$(echo "$part" | grep -o 'https://[^[:space:]]*' | head -1)
    if [ -n "$url" ]; then
        echo "$url"
        return 0
    fi
    return 1
}

# 从本地数据库中批量查询多个用户头像 URL
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

# 通过远程设备批量查询用户头像 URL
get_remote_avatar_urls() {
    local remote_addr="$1"
    local query="$2"
    [ -z "$remote_addr" ] && return 1
    [ -z "$query" ] && return 1

    adb connect "$remote_addr" >/dev/null 2>&1
    sleep 0.3

    local device_serial
    device_serial=$(adb devices | grep "${remote_addr}" | grep "device" | head -1 | awk '{print $1}')
    [ -z "$device_serial" ] && device_serial="$remote_addr"

    adb -s "$device_serial" shell "sh /data/local/tmp/schat/16.sh \"$query\"" 2>/dev/null
}

# ==================== 消息处理函数 ====================

# 构建完整消息格式
build_message() {
    local sender="$1"
    local msg_type="$2"
    local content="$3"
    echo "${sender}:${msg_type}:${content}"
}

# 获取消息大小（字节）
get_message_size() {
    local message="$1"
    echo -n "$message" | wc -c
}

# 检查消息是否过大（超过1MB）
is_message_too_large() {
    local size=$(get_message_size "$1")
    [ $size -gt 1048576 ] && return 0
    return 1
}

# 保存消息文件
save_message() {
    local user1="$1"
    local class="$2"
    local user2="$3"
    local content="$4"
    
    local target_dir="${SDCARD_DIR}/${user1}/${class}/${user2}"
    mkdir -p "$target_dir" 2>/dev/null || return 1
    
    local timestamp=$(get_timestamp_ms)
    echo "$content" > "${target_dir}/${timestamp}.txt"
    
    if [ -f "${target_dir}/${timestamp}.txt" ]; then
        echo "$timestamp"
        return 0
    fi
    return 1
}

# 本地保存消息
save_message_local() {
    local sender="$1"
    local class="$2"
    local receiver="$3"
    local message="$4"
    
    local timestamp=$(get_timestamp_ms)
    local target_dir="${SDCARD_DIR}/${sender}/${class}/${receiver}"
    
    mkdir -p "$target_dir" 2>/dev/null
    if [ ! -d "$target_dir" ]; then
        log_msg "无法创建目录: $target_dir"
        return 1
    fi
    
    local file_path="${target_dir}/${timestamp}.txt"
    echo "$message" > "$file_path"
    
    if [ -f "$file_path" ]; then
        echo "$timestamp"
        return 0
    else
        return 1
    fi
}

# 删除本地消息
delete_local_message() {
    local user1="$1"
    local class="$2"
    local user2="$3"
    local timestamp="$4"
    
    local target_dir="${SDCARD_DIR}/${user1}/${class}/${user2}"
    local file_path="${target_dir}/${timestamp}.txt"
    
    if [ -f "$file_path" ]; then
        rm -f "$file_path"
        if [ ! -f "$file_path" ]; then
            log_msg "已删除本地消息: $file_path"
            return 0
        fi
    fi
    return 1
}

# 获取消息目录
get_message_dir() {
    local user1="$1"
    local class="$2"
    local user2="$3"
    echo "${SDCARD_DIR}/${user1}/${class}/${user2}"
}

# 保存接收到的消息
save_received_message() {
    local user1="$1"
    local class="$2"
    local user2="$3"
    local msg_content="$4"
    
    local target_dir="${SDCARD_DIR}/${user1}/${class}/${user2}"
    local timestamp=$(get_timestamp_ms)
    local file_path="${target_dir}/${timestamp}.txt"
    
    mkdir -p "$target_dir" 2>/dev/null
    if [ ! -d "$target_dir" ]; then
        echo "错误：无法创建目录 $target_dir"
        return 1
    fi
    
    echo "$msg_content" > "$file_path"
    
    if [ -f "$file_path" ]; then
        echo "✓ 已保存: $file_path"
        return 0
    else
        echo "错误：写入文件失败"
        return 1
    fi
}

# ==================== 消息发送函数 ====================

# 测试远程连接（不断开连接）
test_remote_connection() {
    local remote_addr="$1"
    
    log_msg "测试连接 $remote_addr ..."
    
    # 尝试连接（不先断开）
    local result=$(adb connect "$remote_addr" 2>&1)
    
    if echo "$result" | grep -q "connected"; then
        # 测试执行简单命令
        local test_result=$(adb -s "$remote_addr" shell "echo ok" 2>&1)
        
        if echo "$test_result" | grep -q "ok"; then
            return 0
        fi
    fi
    
    return 1
}

# 远程执行（不自动断开连接）
remote_exec_timeout() {
    local ip="$1"
    local cmd="$2"
    local timeout_sec=${3:-$REMOTE_TIMEOUT}
    
    # 连接到目标设备（不先断开）
    local connect_result=$(adb connect "$ip" 2>&1)
    sleep 0.5
    
    if ! echo "$connect_result" | grep -q "connected"; then
        return 1
    fi
    
    # 获取设备序列号
    local device_serial=""
    device_serial=$(adb devices | grep "${ip}" | grep "device" | head -1)
    device_serial=$(echo "$device_serial" | sed 's/[[:space:]].*//')
    
    if [ -z "$device_serial" ]; then
        device_serial="$ip"
    fi
    
    # 执行远程命令
    local result=""
    local ret=0
    
    if command -v timeout >/dev/null 2>&1; then
        result=$(timeout "$timeout_sec" adb -s "$device_serial" shell "$cmd" 2>&1)
        ret=$?
    else
        result=$(adb -s "$device_serial" shell "$cmd" 2>&1)
        ret=$?
    fi
    
    # 不主动断开连接
    
    if [ $ret -eq 0 ]; then
        [ -n "$result" ] && echo "$result"
        return 0
    else
        return 1
    fi
}

# 远程保存消息
save_message_remote() {
    local remote_addr="$1"
    local receiver="$2"
    local class="$3"
    local sender="$4"
    local message="$5"
    
    # 转义消息中的特殊字符
    local escaped_message=$(echo "$message" | sed 's/"/\\"/g' | sed "s/'/\\'/g")
    
    # 构建远程命令
    local remote_cmd="$SAVE_MSG_SCRIPT \"$receiver\" \"$class\" \"$sender\" \"$escaped_message\""
    
    log_msg "执行远程命令: $remote_cmd"
    
    if remote_exec_timeout "$remote_addr" "$remote_cmd" "$REMOTE_TIMEOUT"; then
        return 0
    else
        return 1
    fi
}

# 发送消息主函数
send_message() {
    local sender="$1"
    local class="$2"
    local receiver="$3"
    local msg_type="$4"
    local msg_body="$5"
    local remote_addr="$6"
    
    # 构建完整消息
    local full_message=$(build_message "$sender" "$msg_type" "$msg_body")
    local message_size=$(get_message_size "$full_message")
    
    log_msg "=========================================="
    log_msg "开始发送消息"
    log_msg "发言人: $sender"
    log_msg "班级: $class"
    log_msg "接收人: $receiver"
    log_msg "消息类型: $msg_type"
    log_msg "消息大小: ${message_size} 字节"
    log_msg "远程地址: $remote_addr"
    log_msg "=========================================="
    
    # 检查消息大小
    if is_message_too_large "$full_message"; then
        log_msg "错误：消息过大（超过1MB）"
        return 1
    fi
    
    # 步骤1：本地保存
    log_msg ">>> [1/2] 本地保存"
    local local_timestamp=$(save_message_local "$sender" "$class" "$receiver" "$full_message")
    if [ $? -eq 0 ] && [ -n "$local_timestamp" ]; then
        log_msg "✓ 本地保存成功 (时间戳: $local_timestamp)"
    else
        log_msg "✗ 本地保存失败"
        return 2
    fi
    
    # 步骤2：远程保存（带重试）
    log_msg ">>> [2/2] 远程保存"
    local remote_success=false
    local max_retries=2
    
    for retry in $(seq 1 $max_retries); do
        log_msg "远程尝试 $retry/$max_retries"
        
        if save_message_remote "$remote_addr" "$receiver" "$class" "$sender" "$full_message"; then
            log_msg "✓ 远程保存成功"
            remote_success=true
            break
        fi
        
        if [ $retry -lt $max_retries ]; then
            sleep 1
        fi
    done
    
    if [ "$remote_success" = true ]; then
        log_msg "✓ 消息发送完成"
        return 0
    else
        log_msg "✗ 远程保存失败"
        
        # 回滚：删除本地消息
        log_msg ">>> 回滚操作：删除本地消息"
        delete_local_message "$sender" "$class" "$receiver" "$local_timestamp"
        
        return 3
    fi
}

# ==================== 数据库备份/恢复函数 ====================

# 备份数据库
backup_database() {
    local source_db="/data/data/com.czhl.pass/databases/czhl.db"
    local target_db="/sdcard/schat/czhl.db"
    
    if [ -f "$source_db" ]; then
        mkdir -p /sdcard/schat 2>/dev/null
        cp "$source_db" "$target_db" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_msg "数据库备份成功: $target_db"
            return 0
        else
            log_msg "数据库备份失败"
            return 1
        fi
    else
        log_msg "源数据库不存在: $source_db"
        return 1
    fi
}

# 恢复数据库
restore_database() {
    local source_db="/sdcard/schat/czhl.db"
    local target_db="/data/data/com.czhl.pass/databases/czhl.db"
    
    if [ -f "$source_db" ]; then
        mkdir -p /data/data/com.czhl.pass/databases 2>/dev/null
        cp "$source_db" "$target_db" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_msg "数据库恢复成功: $source_db -> $target_db"
            return 0
        else
            log_msg "数据库恢复失败"
            return 1
        fi
    else
        log_msg "源数据库文件不存在: $source_db"
        return 1
    fi
}

# ==================== 应用管理函数 ====================

# 禁用应用
disable_app() {
    local package="$1"
    if pm list packages | grep -q "$package"; then
        log_msg "禁用应用: $package"
        pm disable "$package" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_msg "已禁用: $package"
            return 0
        else
            log_msg "禁用失败: $package"
            return 1
        fi
    else
        log_msg "应用不存在或已禁用: $package"
        return 1
    fi
}

# 启用应用
enable_app() {
    local package="$1"
    if pm list packages | grep -q "$package"; then
        log_msg "启用应用: $package"
        pm enable "$package" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_msg "已启用: $package"
            return 0
        else
            log_msg "启用失败: $package"
            return 1
        fi
    else
        log_msg "应用不存在: $package"
        return 1
    fi
}

# 启动应用
start_app() {
    local package="$1"
    
    if ! pm list packages | grep -q "$package"; then
        log_msg "应用不存在: $package"
        return 1
    fi
    
    log_msg "启动应用: $package"
    
    # 获取主活动
    local main_activity=""
    main_activity=$(cmd package resolve-activity --brief "$package" 2>/dev/null | tail -n 1)
    
    if [ -z "$main_activity" ] || [ "$main_activity" = "$package" ]; then
        main_activity=$(dumpsys package "$package" 2>/dev/null | grep -A 1 "android.intent.action.MAIN" | grep "$package/" | head -1)
        main_activity=$(echo "$main_activity" | sed 's/.*\([a-zA-Z][a-zA-Z0-9_.]*\/[a-zA-Z][a-zA-Z0-9_.]*\).*/\1/')
    fi
    
    if [ -n "$main_activity" ]; then
        am start -n "$main_activity" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_msg "已启动: $package (am start)"
            return 0
        fi
    fi
    
    # 备用方案：使用 monkey
    log_msg "尝试使用 monkey 启动"
    monkey -p "$package" -c android.intent.category.LAUNCHER 1 2>/dev/null
    if [ $? -eq 0 ]; then
        log_msg "已启动: $package (monkey)"
        return 0
    fi
    
    log_msg "启动失败: $package"
    return 1
}

# 强制停止应用
force_stop_app() {
    local package="$1"
    
    log_msg "强制停止应用: $package"
    
    # 杀死进程
    local pids=$(pgrep -f "$package" 2>/dev/null)
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill -9 "$pid" 2>/dev/null
            log_msg "已杀死进程: $pid"
        done
    fi
    
    am force-stop "$package" 2>/dev/null
    log_msg "已执行 force-stop"
    return 0
}

# 杀死应用并恢复数据库（循环多次）
kill_and_restore() {
    local package="$1"
    local times=${2:-5}
    
    log_msg "循环杀死应用并恢复数据 ($times 次)"
    
    local i=1
    while [ $i -le $times ]; do
        log_msg "========== 第 $i 次操作 =========="
        
        force_stop_app "$package"
        restore_database
        
        if [ $i -lt $times ]; then
            sleep 1
        fi
        
        i=$((i + 1))
    done
}

# ==================== Activity 检测函数 ====================

# 检查当前活动是否为目标Activity
is_target_activity() {
    local target="$1"
    
    [ -z "$target" ] && return 1
    
    local current_info=""
    
    # 方法1: Android 8+ 最常用
    current_info=$(dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp')
    
    # 方法2: 备用
    if [ -z "$current_info" ]; then
        current_info=$(dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|mTopResumedActivity')
    fi
    
    # 方法3: 最底层
    if [ -z "$current_info" ]; then
        current_info=$(dumpsys activity top 2>/dev/null | grep -m1 'ACTIVITY' | head -1)
    fi
    
    if echo "$current_info" | grep -qi "$target"; then
        log_msg "匹配成功: 当前活动包含 $target"
        return 0
    else
        local current_activity=$(echo "$current_info" | head -1 | grep -oE '[a-zA-Z][a-zA-Z0-9_.]*/[a-zA-Z][a-zA-Z0-9_.]*' | head -1)
        [ -n "$current_activity" ] && log_msg "当前活动: $current_activity"
        return 1
    fi
}

# ==================== 远程设备用户列表函数 ====================

# 获取远程设备的用户列表（不断开连接）
get_remote_user_list() {
    local ip="$1"
    
    # 连接设备（不先断开）
    adb connect "$ip" >/dev/null 2>&1
    sleep 0.3
    
    # 获取 USER 文件内容
    local result=$(adb -s "$ip" shell cat /sdcard/schat/USER 2>/dev/null)
    
    # 不断开连接
    
    echo "$result"
}

# ==================== 同步函数 ====================

# 同步USER列表到所有设备（跳过主IP，不断开连接）
sync_user_list_to_all() {
    local main_ip="$1"
    
    if [ ! -f "$USER_LIST" ]; then
        log_msg "USER列表不存在，退出"
        return 1
    fi
    
    if [ -z "$main_ip" ]; then
        [ -f "$MAIN_IP_FILE" ] && main_ip=$(cat "$MAIN_IP_FILE" 2>/dev/null)
    fi
    
    [ -z "$main_ip" ] && return 1
    
    log_msg "开始同步USER列表到所有设备（跳过主IP: $main_ip）"
    
    local all_ips=$(get_all_ips)
    [ -z "$all_ips" ] && return 1
    
    for ip in $all_ips; do
        [ -z "$ip" ] && continue
        
        if [ "$ip" = "$main_ip" ]; then
            log_msg "跳过主IP: $ip"
            continue
        fi
        
        log_msg "同步到: $ip"
        
        adb connect "$ip" 2>/dev/null 1>/dev/null
        
        if adb -s "$ip" push "$USER_LIST" /sdcard/schat/USER 2>/dev/null; then
            log_msg "同步成功: $ip"
        else
            log_msg "同步失败: $ip"
        fi
        # 不断开连接
    done
    
    log_msg "同步完成"
}

# ==================== 清理函数 ====================

# 清理脚本日志
clean_script_logs() {
    rm -rf "${LOGS_DIR}"/* 2>/dev/null
    rm -rf "${NAME_DIR}"/* 2>/dev/null
    rm -rf "${PROCESSED_DIR}"/* 2>/dev/null
    rm -f "${MATCH_DIR}/.last_match_time" 2>/dev/null
    log_msg "已清理脚本日志"
}

# 清理聊天记录
clean_chat_records() {
    find "$SDCARD_DIR" -type f -name "*.txt" -delete 2>/dev/null
    log_msg "已删除所有聊天记录"
}

# 每日清理任务
daily_cleanup() {
    local today=$(date +%Y%m%d)
    
    if [ "$(cat "$FIRSTTIME_FILE" 2>/dev/null)" != "$today" ]; then
        log_msg "每日首次运行，执行清理任务"
        
        clean_script_logs
        
        # 每7天清理聊天记录
        local current_week=$((today / 7))
        if [ "$(cat "$LAST_CLEAN_WEEK_FILE" 2>/dev/null)" != "$current_week" ]; then
            clean_chat_records
            echo "$current_week" > "$LAST_CLEAN_WEEK_FILE"
        fi
        
        echo "$today" > "$FIRSTTIME_FILE"
    fi
}

# ==================== ADB 连接函数 ====================

# 连接远程设备（带超时和重试，不自动断开）
connect_remote_device() {
    local ip="$1"
    local timeout_sec=${2:-10}
    
    log_msg "目标IP: $ip"
    log_msg "开始尝试连接..."
    
    while true; do
        log_msg "正在执行: adb connect $ip"
        
        if command -v timeout >/dev/null 2>&1; then
            $ADB_SCRIPT connect "$ip" &
            local pid=$!
            
            for i in $(seq 1 $timeout_sec); do
                sleep 1
                if ! kill -0 $pid 2>/dev/null; then
                    wait $pid
                    if [ $? -eq 0 ]; then
                        log_msg "连接成功！"
                        return 0
                    else
                        break
                    fi
                fi
            done
            
            log_msg "连接超时（>${timeout_sec}秒），强制终止"
            kill -9 $pid 2>/dev/null
            wait $pid 2>/dev/null
        else
            $ADB_SCRIPT connect "$ip" &
            local pid=$!
            sleep $timeout_sec
            
            if kill -0 $pid 2>/dev/null; then
                log_msg "连接超时（>${timeout_sec}秒），强制终止"
                kill -9 $pid 2>/dev/null
                wait $pid 2>/dev/null
            else
                wait $pid
                if [ $? -eq 0 ]; then
                    log_msg "连接成功！"
                    return 0
                fi
            fi
        fi
        
        log_msg "连接失败，1秒后重试..."
        sleep 1
    done
}

# ==================== 入口调度函数 ====================

# 根据脚本名派发执行入口
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
        *) log_msg "未知脚本: $script_name" ; exit 1 ;;
    esac
}

script_1_main() {
    init_std_dirs
    check_single_instance
    log_msg "日志监控脚本启动 (目标: $TARGET_KEYWORD)"
    log_msg "=========================================="
    log_msg "初始化完成，进入业务监听"
    log_msg "=========================================="

    local last_match=0
    while ! check_stop; do
        update_heartbeat
        maintain_scripts $SCRIPT_NUM

        local logs=$(logcat -d | tail -200)

        if echo "$logs" | grep -q "$TARGET_KEYWORD"; then
            local now=$(date +%s)
            if [ -f "${MATCH_DIR}/.last_match_time" ]; then
                last_match=$(cat "${MATCH_DIR}/.last_match_time" 2>/dev/null || echo 0)
            fi

            if [ $((now - last_match)) -gt $MATCH_COOLDOWN ]; then
                echo "$now" > "${MATCH_DIR}/.last_match_time"
                local log_file="${LOG_DIR}/log_$(date +'%Y%m%d_%H%M%S').txt"
                {
                    echo "检测时间: $(date '+%Y-%m-%d %H:%M:%S')"
                    echo "$logs" | grep "$TARGET_KEYWORD" | head -20
                } > "$log_file"
                log_msg "✓ 捕获目标日志: $log_file"
                log_msg "执行数据库备份..."
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
    log_msg "=========================================="
    log_msg "初始化完成，进入业务处理"
    log_msg "=========================================="

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
    if [ -f "${BASE_DIR}/13.sh" ]; then
        log_msg "启动 13.sh"
        . "${BASE_DIR}/13.sh"
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
    log_msg "执行 start.sh，接收参数: $USER_NAME"
    echo "$USER_NAME" > "$USER_NOW"
    log_msg "已写入: $USER_NOW -> $USER_NAME"
    disable_app "$TARGET_PACKAGE_DISABLE"
    start_app "$TARGET_PACKAGE_START"
    exit 0
}

script_5_main() {
    log_msg "执行恢复脚本: restart_pass.sh"
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
    if ! validate_username "$clean_user"; then
        exit 1
    fi
    create_user_dir "$clean_user"
    add_user_to_list "$clean_user"
    exit 0
}

script_7_main() {
    [ $# -ne 3 ] && { echo "用法: $0 <用户名1> <班级> <用户名2>"; exit 1; }
    TARGET_DIR="${SDCARD_DIR}/$1/$2/$3"
    if [ -d "$TARGET_DIR" ]; then
        echo "目录已存在: $TARGET_DIR"
        exit 0
    fi
    if mkdir -p "$TARGET_DIR" 2>/dev/null; then
        chmod 755 "$TARGET_DIR" 2>/dev/null
        echo "创建成功: $TARGET_DIR"
        exit 0
    else
        echo "创建失败: $TARGET_DIR"
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
    [ ! -f "$ADB_SCRIPT" ] && { log_msg "错误: 找不到adb"; exit 1; }
    [ ! -f "$MAIN_IP_FILE" ] && { log_msg "错误: 找不到IP文件"; exit 1; }
    local IP=$(cat "$MAIN_IP_FILE" | tr -d '[:space:]')
    [ -z "$IP" ] && { log_msg "错误: IP为空"; exit 1; }
    connect_remote_device "$IP"
}

script_14_main() {
    SCRIPT_NAME="14.sh"
    SCRIPT_NUM=14
    sync_user_list_to_all "$(cat "$MAIN_IP_FILE" 2>/dev/null)"
}

script_15_main() {
    init_std_dirs
    stop_all_scripts
}

script_16_main() {
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <姓名> 或 <姓名1>|<姓名2>|..."
        exit 1
    fi
    local QUERY="$1"
    get_avatar_urls_from_db "$QUERY"
    exit $?
}

script_17_main() {
    if [ $# -ne 2 ]; then
        echo "用法: $0 <IP:端口> <用户名或批量用户>"
        exit 1
    fi
    local REMOTE_ADDR="$1"
    local QUERY="$2"
    [ -z "$REMOTE_ADDR" ] && { echo "错误: IP 为空"; exit 1; }
    [ -z "$QUERY" ] && { echo "错误: 查询内容为空"; exit 1; }
    get_remote_avatar_urls "$REMOTE_ADDR" "$QUERY"
}

stop_all_scripts() {
    log_msg "=========================================="
    log_msg "开始停止所有 Schat 脚本"
    log_msg "=========================================="
    log_msg "[1/5] 写入停止标志"
    mkdir -p "$(dirname "$STOP_FLAG")" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$STOP_FLAG"
    log_msg "✓ 停止标志已创建: $STOP_FLAG"
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
                log_msg "  ✓ 已终止"
            else
                log_msg "脚本 ${num}.sh 已自清理 (PID: ${pid:-无})"
            fi
        else
            log_msg "脚本 ${num}.sh 未运行或已自清理"
        fi
    done
    log_msg "[3/5] 清理看门狗文件"
    for num in 1 2 3; do
        rm -f "${WATCHDOG_DIR}/${num}.pid" 2>/dev/null
        rm -f "${WATCHDOG_DIR}/${num}.heartbeat" 2>/dev/null
    done
    log_msg "✓ 已清理看门狗文件"
    log_msg "[4/5] 清理残留日志"
    rm -f "${NAME_DIR}/name_*.txt" 2>/dev/null
    rm -f "${PROCESSED_DIR}"/*.txt 2>/dev/null
    rm -f "${MATCH_DIR}/.last_match_time" 2>/dev/null
    log_msg "✓ 已清理残留日志"
    log_msg "[5/5] 删除停止标志"
    rm -f "$STOP_FLAG" 2>/dev/null
    log_msg "✓ 已删除停止标志"
    log_msg "=========================================="
    log_msg "停止完成"
    log_msg "=========================================="
}
