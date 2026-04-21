#!/system/bin/sh

# ============================================
# Schat 系统配置文件
# 版本: 3.0 - 纯配置版
# ============================================

# ==================== 路径配置 ====================
BASE_DIR="/data/local/tmp/schat"
SDCARD_DIR="/sdcard/schat"
WATCHDOG_DIR="${BASE_DIR}/watchdog"

# 子目录
LOG_DIR="${BASE_DIR}/getlog"
MATCH_DIR="${BASE_DIR}/match_state"
NAME_DIR="${BASE_DIR}/allname"
PROCESSED_DIR="${BASE_DIR}/processed"
LOGS_DIR="${BASE_DIR}/logs"

# ==================== 文件配置 ====================
USER_LIST="${SDCARD_DIR}/USER"
USER_NOW="${SDCARD_DIR}/usernow"
DEVICES_FILE="${SDCARD_DIR}/devicesIP"
MAIN_IP_FILE="${SDCARD_DIR}/mainIP"
STOP_FLAG="${BASE_DIR}/stop_all"
FAILED_LOG="${SDCARD_DIR}/failed_match.log"
FIRSTTIME_FILE="${BASE_DIR}/firsttime"
LAST_CLEAN_WEEK_FILE="${BASE_DIR}/last_clean_week"

# ==================== 脚本路径 ====================
ADB_SCRIPT="${BASE_DIR}/adb"
SEND_MSG_SCRIPT="${BASE_DIR}/10.sh"
SAVE_MSG_SCRIPT="${BASE_DIR}/9.sh"
CREATE_DIR_SCRIPT="${BASE_DIR}/7.sh"

# ==================== 应用包名 ====================
TARGET_PACKAGE_DISABLE="com.czhl.pass"
TARGET_PACKAGE_START="com.example.rootwebviewdemo"
TARGET_ACTIVITY="com.czhl.pass.ui.query.QueryActivity"

# ==================== 监控配置 ====================
TARGET_KEYWORD="识别成功"
HEARTBEAT_TIMEOUT=5
MATCH_COOLDOWN=5
LOOP_SLEEP=1
REMOTE_TIMEOUT=5

# ==================== 调试开关 ====================
DEBUG=0
