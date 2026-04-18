#!/system/bin/sh

# ============================================
# Schat 系统配置文件
# 版本: 3.0
# ============================================

# ==================== 路径配置 ====================
readonly BASE_DIR="/data/local/tmp/schat"
readonly SDCARD_DIR="/sdcard/schat"
readonly WATCHDOG_DIR="${BASE_DIR}/watchdog"

# 子目录
readonly LOG_DIR="${BASE_DIR}/getlog"
readonly MATCH_DIR="${BASE_DIR}/match_state"
readonly NAME_DIR="${BASE_DIR}/allname"
readonly PROCESSED_DIR="${BASE_DIR}/processed"
readonly LOGS_DIR="${BASE_DIR}/logs"

# ==================== 文件配置 ====================
readonly USER_LIST="${SDCARD_DIR}/USER"
readonly USER_NOW="${SDCARD_DIR}/usernow"
readonly DEVICES_FILE="${SDCARD_DIR}/devicesIP"
readonly MAIN_IP_FILE="${SDCARD_DIR}/mainIP"
readonly STOP_FLAG="${BASE_DIR}/stop_all"
readonly FAILED_LOG="${SDCARD_DIR}/failed_match.log"
readonly FIRSTTIME_FILE="${BASE_DIR}/firsttime"
readonly LAST_CLEAN_WEEK_FILE="${BASE_DIR}/last_clean_week"

# ==================== 脚本路径 ====================
readonly SCRIPT_DIR="${BASE_DIR}"
readonly ADB_SCRIPT="${SCRIPT_DIR}/adb"
readonly SEND_MSG_SCRIPT="${SCRIPT_DIR}/10.sh"
readonly SAVE_MSG_SCRIPT="${SCRIPT_DIR}/9.sh"
readonly CREATE_DIR_SCRIPT="${SCRIPT_DIR}/7.sh"

# ==================== 应用包名 ====================
readonly TARGET_PACKAGE_DISABLE="com.czhl.pass"
readonly TARGET_PACKAGE_START="com.example.rootwebviewdemo"
readonly ADB_ACTIVITY="facecapture.hik.com.openadb.MainActivity"
readonly TARGET_ACTIVITY="com.czhl.pass.ui.query.QueryActivity"

# ==================== 监控配置 ====================
readonly TARGET_KEYWORD="识别成功"
readonly HEARTBEAT_TIMEOUT=5
readonly MATCH_COOLDOWN=5
readonly LOOP_SLEEP=1
readonly REMOTE_TIMEOUT=5

# ==================== 调试开关 ====================
# 设置为 1 开启调试日志
export DEBUG=0