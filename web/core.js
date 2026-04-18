// Schat - 统一函数库

// ========== 原生桥接 ==========
function root_cmd(mycmd) {
    const raw = NativeBridge.root_cmd(mycmd);
    return JSON.parse(raw);
}

// ========== 防XSS ==========
function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/[&<>]/g, function(m) {
        if (m === '&') return '&amp;';
        if (m === '<') return '&lt;';
        if (m === '>') return '&gt;';
        return m;
    });
}

// ========== Toast提示 ==========
let toastTimer = null;
function showToast(msg, duration = 2000) {
    const existingToast = document.querySelector('.toast');
    if (existingToast) existingToast.remove();
    if (toastTimer) clearTimeout(toastTimer);
    
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = msg;
    document.body.appendChild(toast);
    
    toastTimer = setTimeout(() => {
        toast.remove();
        toastTimer = null;
    }, duration);
}

// ========== 状态信息 ==========
function showStatus(elementId, msg, type) {
    const statusDiv = document.getElementById(elementId);
    if (!statusDiv) return;
    
    statusDiv.textContent = msg;
    statusDiv.className = 'status';
    statusDiv.style.display = 'block';
    
    if (type === 'success') {
        statusDiv.classList.add('status-success');
    } else if (type === 'error') {
        statusDiv.classList.add('status-error');
    } else if (type === 'loading') {
        statusDiv.classList.add('status-loading');
    }
    
    if (type !== 'loading') {
        setTimeout(() => {
            if (statusDiv) {
                statusDiv.style.display = 'none';
                statusDiv.className = 'status';
            }
        }, 3000);
    }
}

function hideStatus(elementId) {
    const statusDiv = document.getElementById(elementId);
    if (statusDiv) {
        statusDiv.style.display = 'none';
        statusDiv.className = 'status';
    }
}

// ========== URL参数 ==========
function getUrlParam(name) {
    const urlParams = new URLSearchParams(window.location.search);
    return urlParams.get(name);
}

// ========== 用户相关 ==========
function getCurrentUser() {
    const result = root_cmd("cat /sdcard/schat/usernow 2>/dev/null");
    const output = result[0];
    const exitCode = result[2];
    
    if (exitCode === 0 && output && output.trim()) {
        return output.trim();
    }
    return null;
}

function setCurrentUser(username) {
    if (!username) return false;
    root_cmd(`echo "${username}" > /sdcard/schat/usernow 2>/dev/null`);
    return getCurrentUser() === username;
}

function logout() {
    root_cmd("rm -f /sdcard/schat/usernow 2>/dev/null");
    root_cmd("sh /data/local/tmp/schat/5.sh 2>/dev/null");
}

// ========== 头像相关 ==========
// 头像缓存（避免重复请求）
const avatarCache = {};

// 验证URL格式
function isValidUrl(url) {
    if (!url) return false;
    return url.startsWith('http://') || url.startsWith('https://');
}

// 解析批量查询的响应
// 输入: "用户1:https://...\n用户2:https://...\n用户3:"
// 输出: { "用户1": "https://...", "用户2": "https://...", "用户3": null }
function parseAvatarResponse(response) {
    const result = {};
    if (!response) return result;
    
    const lines = response.trim().split('\n');
    for (const line of lines) {
        const colonIdx = line.indexOf(':');
        if (colonIdx > 0) {
            const name = line.substring(0, colonIdx).trim();
            const url = line.substring(colonIdx + 1).trim();
            result[name] = isValidUrl(url) ? url : null;
        }
    }
    return result;
}

// 单个查询（向后兼容）
function getAvatarUrl(username, classIP) {
    if (!username) return null;
    
    const cacheKey = classIP ? `${username}@${classIP}` : username;
    if (avatarCache[cacheKey]) {
        return avatarCache[cacheKey];
    }
    
    try {
        // 优先尝试本地数据库（16h）
        const localResult = root_cmd(`sh /data/local/tmp/schat/16h "v/null`);
        const localUrl = localResult[0] ? localResult[0].trim() : null;
        
        if (isValidUrl(localUrl)) {
            avatarCache[cacheKey] = localUrl;
            return localUrl;
        }
        
        // 如果本地失败且提供了classIP，尝试远程设备（通过17.sh）
        if (classIP) {
            const remoteResult = root_cmd(`sh /data/local/tmp/schat/17.sh "${classIP}" "${username}" 2>/dev/null`);
            const remoteUrl = remoteResult[0] ? remoteResult[0].trim() : null;
            
            if (isValidUrl(remoteUrl)) {
                avatarCache[cacheKey] = remoteUrl;
                return remoteUrl;
            }
        }
    } catch (err) {
        console.warn(`获取 ${username} 头像失败:`, err);
    }
    
    return null;
}

// 批量获取头像 URL（同一 IP 的请求合并）
// 用法：batchAvatarRequest([{name:'张三', ip:'192.168.1.100:5555'}, ...])
// 返回：{"192.168.1.100:5555": {张三: url1, 李四: url2}, ...}
function batchAvatarRequest(users) {
    if (!users || users.length === 0) return {};
    
    // 1. 按 IP 分组
    const groupByIp = {};
    for (const user of users) {
        const ip = user.ip || 'local';
        if (!groupByIp[ip]) {
            groupByIp[ip] = [];
        }
        groupByIp[ip].push(user.name);
    }
    
    // 2. 按组发送请求
    const result = {};
    for (const ip in groupByIp) {
        const names = groupByIp[ip];
        const cacheKey = `batch_${ip}`;
        
        // 检查缓存
        if (avatarCache[cacheKey] !== undefined) {
            result[ip] = avatarCache[cacheKey];
            continue;
        }
        
        // 构建批量查询字符串 "名字1|名字2|名字3"
        const queryStr = names.join('|');
        
        try {
            let response = null;
            
            if (ip === 'local') {
                // 本地查询
                const localResult = root_cmd(`sh /data/local/tmp/schat/16h "v/null`);
                response = localResult[0] ? localResult[0].trim() : '';
            } else {
                // 远程查询
                const remoteResult = root_cmd(`sh /data/local/tmp/schat/17.sh "${ip}" "${queryStr}" 2>/dev/null`);
                response = remoteResult[0] ? remoteResult[0].trim() : '';
            }
            
            // 解析响应
            const parsed = parseAvatarResponse(response);
            
            // 缓存单个结果
            for (const name in parsed) {
                const url = parsed[name];
                const singleCacheKey = ip === 'local' ? name : `${name}@${ip}`;
                if (url) {
                    avatarCache[singleCacheKey] = url;
                }
            }
            
            // 缓存整组结果
            avatarCache[cacheKey] = parsed;
            result[ip] = parsed;
            
        } catch (err) {
            console.warn(`批量获取 ${ip} 头像失败:`, err);
            result[ip] = {};
        }
    }
    
    return result;
}

// 获取对话列表并按班级分组
function getChatsGroupedByClass(currentUser) {
    const chats = getChatList(currentUser);
    const grouped = {};
    
    for (const chat of chats) {
        if (!grouped[chat.className]) {
            grouped[chat.className] = [];
        }
        grouped[chat.className].push(chat);
    }
    
    return grouped;
}

// ========== 班级相关 ==========
function getClassList() {
    const result = root_cmd("sh /data/local/tmp/schat/11.sh 0 2>/dev/null");
    if (result[2] !== 0 || !result[0] || !result[0].trim()) return [];
    
    const lines = result[0].trim().split('\n');
    const classes = [];
    for (const line of lines) {
        const className = line.trim();
        if (className) {
            const ipResult = root_cmd(`sh /data/local/tmp/schat/11.sh 1 "${className}" 2>/dev/null`);
            const ip = ipResult[0] ? ipResult[0].trim() : '';
            if (ip) classes.push({ name: className, ip: ip });
        }
    }
    return classes;
}

function getClassIP(className) {
    if (!className) return null;
    const result = root_cmd(`sh /data/local/tmp/schat/11.sh 1 "${className}" 2>/dev/null`);
    if (result[2] !== 0) return null;
    return result[0] ? result[0].trim() : null;
}

// ========== 用户列表相关（修复版）==========
function getRemoteUserList(ip, currentUser) {
    if (!ip) {
        showToast(`❌ 无法获取设备地址`, 1500);
        return [];
    }
    
    showToast(`🔍 正在获取用户列表...`, 1000);
    
    const result = root_cmd(`sh /data/local/tmp/schat/12.sh "${ip}" 2>/dev/null`);
    
    const stdout = result[0] || '';
    const stderr = result[1] || '';
    const exitCode = result[2];
    
    console.log(`getRemoteUserList - IP: ${ip}, exitCode: ${exitCode}`);
    console.log(`stdout: ${stdout.substring(0, 200)}`);
    if (stderr) console.log(`stderr: ${stderr}`);
    
    if (exitCode !== 0) {
        let errorMsg = stderr || `脚本执行失败，退出码: ${exitCode}`;
        showToast(`❌ ${errorMsg}`, 2000);
        return [];
    }
    
    if (!stdout || !stdout.trim()) {
        showToast(`⚠️ 该班级暂无用户`, 1500);
        return [];
    }
    
    let allUsers = stdout.trim().split('\n').filter(u => u && u.trim());
    showToast(`📊 找到 ${allUsers.length} 个用户`, 1000);
    
    if (currentUser) {
        const beforeCount = allUsers.length;
        allUsers = allUsers.filter(u => u !== currentUser);
        const afterCount = allUsers.length;
        if (beforeCount !== afterCount) {
            showToast(`✓ 已排除自己，剩余 ${afterCount} 人`, 1500);
        }
    }
    
    return allUsers;
}

function getRemoteUserListAsync(ip) {
    return new Promise((resolve) => {
        try {
            if (typeof root_cmd !== 'function') {
                resolve({ users: null, error: 'root_cmd 函数不存在' });
                return;
            }
            
            const result = root_cmd(`sh /data/local/tmp/schat/12.sh "${ip}"`);
            
            if (!result || !Array.isArray(result) || result.length < 3) {
                resolve({ users: null, error: `返回值格式异常: ${typeof result}` });
                return;
            }
            
            const [stdout, stderr, code] = result;
            
            if (code !== 0) {
                const errorMsg = stderr && stderr.trim() ? stderr : `脚本执行失败，退出码: ${code}`;
                resolve({ users: null, error: errorMsg });
                return;
            }
            
            let users = [];
            if (stdout && typeof stdout === 'string') {
                users = stdout.split('\n')
                    .map(line => line.trim())
                    .filter(line => line.length > 0);
            }
            
            resolve({ users: users, error: null });
            
        } catch (err) {
            resolve({ users: null, error: err.message || String(err) });
        }
    });
}

// ========== 聊天相关 ==========
function getChatDir(currentUser, className, otherUser) {
    return `/sdcard/schat/${currentUser}/${className}/${otherUser}`;
}

function ensureChatDir(currentUser, className, otherUser) {
    const result = root_cmd(`sh /data/local/tmp/schat/7.sh "${currentUser}" "${className}" "${otherUser}" 2>/dev/null`);
    return result[2] === 0;
}

function getMessageFiles(chatDir) {
    const result = root_cmd(`ls ${chatDir}/*.txt 2>/dev/null | sort -t'/' -k6 -n`);
    if (result[2] !== 0 || !result[0] || !result[0].trim()) return [];
    return result[0].trim().split('\n').filter(f => f && f.trim());
}

function parseMessageFile(filePath, currentUser) {
    const result = root_cmd(`cat "${filePath}" 2>/dev/null`);
    const content = result[0] ? result[0].trim() : '';
    if (result[2] !== 0 || !content) return null;
    
    const colon1 = content.indexOf(':');
    const colon2 = content.indexOf(':', colon1 + 1);
    if (colon1 === -1 || colon2 === -1) return null;
    
    const sender = content.substring(0, colon1);
    const type = content.substring(colon1 + 1, colon2);
    const msgContent = content.substring(colon2 + 1);
    const fileName = filePath.split('/').pop();
    const timestamp = fileName.replace('.txt', '');
    
    let displayContent = msgContent;
    if (type === '1') {
        displayContent = '📷 [图片消息]';
    }
    
    return {
        sender: sender,
        type: type,
        content: msgContent,
        displayContent: displayContent,
        timestamp: timestamp,
        displayTime: formatTimestamp(timestamp),
        isSelf: sender === currentUser
    };
}

function loadMessages(currentUser, className, otherUser) {
    if (!currentUser || !otherUser || !className) return [];
    
    const chatDir = getChatDir(currentUser, className, otherUser);
    const files = getMessageFiles(chatDir);
    const messages = [];
    
    for (const file of files) {
        const msg = parseMessageFile(file, currentUser);
        if (msg) messages.push(msg);
    }
    
    messages.sort((a, b) => parseInt(a.timestamp) - parseInt(b.timestamp));
    return messages;
}

function sendTextMessage(currentUser, className, otherUser, content) {
    if (!currentUser || !otherUser || !className) {
        return { success: false, error: '请先登录或选择聊天对象' };
    }
    if (!content || content.trim() === '') {
        return { success: false, error: '请输入消息内容' };
    }
    
    const remoteIP = getClassIP(className);
    if (!remoteIP) {
        return { success: false, error: '无法获取对方设备地址' };
    }
    
    const result = root_cmd(`sh /data/local/tmp/schat/10.sh "${currentUser}" "${className}" "${otherUser}" "0" "${content.replace(/"/g, '\\"')}" "${remoteIP}"`);
    
    if (result[2] === 0) {
        return { success: true };
    } else {
        let errorMsg = '发送失败';
        if (result[1] && result[1].trim()) {
            errorMsg = result[1].trim();
        } else if (result[0] && result[0].trim()) {
            errorMsg = result[0].trim();
        } else {
            errorMsg = `脚本执行失败，退出码: ${result[2]}`;
        }
        return { success: false, error: errorMsg };
    }
}

function createChatDirectory(currentUser, selectedClass, otherUser, selectedClassIP) {
    if (!currentUser || !selectedClass || !otherUser || !selectedClassIP) {
        return { success: false, error: '缺少必要参数' };
    }
    
    const cmd = `sh /data/local/tmp/schat/8.sh "${currentUser}" "${selectedClass}" "${otherUser}" "${selectedClassIP}"`;
    const result = root_cmd(cmd);
    
    const exitCode = result[2];
    const stdout = result[0] || '';
    const stderr = result[1] || '';
    
    console.log(`createChatDirectory - exitCode: ${exitCode}`);
    console.log(`stdout: ${stdout}`);
    if (stderr) console.log(`stderr: ${stderr}`);
    
    if (exitCode === 0) {
        return { success: true, message: stdout };
    } else {
        return { success: false, error: stderr || stdout || `脚本执行失败，退出码: ${exitCode}` };
    }
}

// ========== 时间格式化 ==========
function formatTimestamp(timestamp) {
    if (!timestamp || timestamp.length < 10) return '';
    
    const seconds = parseInt(timestamp.substring(0, 10));
    const millis = parseInt(timestamp.substring(10) || '0');
    
    const date = new Date(seconds * 1000 + millis);
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const msgDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    
    const pad = (n) => n.toString().padStart(2, '0');
    
    if (msgDate.getTime() === today.getTime()) {
        return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
    } else if (msgDate.getTime() === today.getTime() - 86400000) {
        return `昨天 ${pad(date.getHours())}:${pad(date.getMinutes())}`;
    } else {
        return `${date.getMonth() + 1}/${date.getDate()} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
    }
}

// ========== 导航 ==========
function goBack(defaultUrl = 'index.html') {
    if (document.referrer && document.referrer.includes(window.location.host)) {
        window.history.back();
    } else {
        window.location.href = defaultUrl;
    }
}

// ========== 聊天列表相关 ==========
function getChatList(currentUser) {
    if (!currentUser) return [];
    
    const classCmd = `ls -d /sdcard/schat/${currentUser}/*/ 2>/dev/null`;
    const classResult = root_cmd(classCmd);
    if (classResult[2] !== 0 || !classResult[0] || !classResult[0].trim()) return [];
    
    const classDirs = classResult[0].trim().split('\n');
    const chats = [];
    
    for (const classDir of classDirs) {
        const classPath = classDir.replace(/\/$/, '');
        const className = classPath.split('/').pop();
        if (!className) continue;
        
        const userCmd = `ls -d ${classPath}/*/ 2>/dev/null`;
        const userResult = root_cmd(userCmd);
        if (userResult[2] !== 0 || !userResult[0] || !userResult[0].trim()) continue;
        
        const userDirs = userResult[0].trim().split('\n');
        for (const userDir of userDirs) {
            const userPath = userDir.replace(/\/$/, '');
            const otherUser = userPath.split('/').pop();
            if (otherUser && otherUser !== currentUser) {
                chats.push({
                    name: otherUser,
                    className: className,
                    path: userPath
                });
            }
        }
    }
    return chats;
}

function getLastMessagePreview(currentUser, chat) {
    if (!currentUser) return '';
    
    const cmd = `ls -t /sdcard/schat/${currentUser}/${chat.className}/${chat.name}/*.txt 2>/dev/null | head -1`;
    const result = root_cmd(cmd);
    const latestFile = result[0] ? result[0].trim() : '';
    if (!latestFile) return '暂无消息';
    
    const catResult = root_cmd(`cat "${latestFile}" 2>/dev/null`);
    const content = catResult[0] ? catResult[0].trim() : '';
    if (!content) return '暂无消息';
    
    const parts = content.split(':');
    if (parts.length >= 3) {
        const sender = parts[0];
        const type = parts[1];
        let msgContent = parts.slice(2).join(':');
        if (type === '1') {
            msgContent = '📷 图片';
        } else if (msgContent.length > 20) {
            msgContent = msgContent.substring(0, 20) + '...';
        }
        return sender === currentUser ? `我: ${msgContent}` : `${sender}: ${msgContent}`;
    }
    return content.length > 20 ? content.substring(0, 20) + '...' : content;
}

// ========== 注册相关 ==========
function isValidChineseName(str) {
    if (!str || typeof str !== 'string') return false;
    return /^[\u4e00-\u9fa5]{2,4}$/.test(str.trim());
}

function registerUser(username) {
    if (!isValidChineseName(username)) {
        return { success: false, message: '姓名必须是2-4个汉字' };
    }
    
    const result = root_cmd(`sh /data/local/tmp/schat/6.sh "${username.trim()}"`);
    
    if (result[2] === 0) {
        return { success: true, message: `注册成功！欢迎 ${username}` };
    } else {
        let errorMsg = '注册失败';
        if (result[1] && result[1].trim()) {
            errorMsg = `注册失败：${result[1].trim()}`;
        } else if (result[0] && result[0].includes('错误')) {
            const errLine = result[0].split('\n').find(l => l.includes('✗') || l.includes('错误'));
            if (errLine) errorMsg = `注册失败：${errLine.trim()}`;
        }
        return { success: false, message: errorMsg };
    }
}

// ========== 自动刷新定时器管理 ==========
let autoRefreshTimer = null;

function startAutoRefresh(callback, interval = 3000) {
    stopAutoRefresh();
    autoRefreshTimer = setInterval(callback, interval);
}

function stopAutoRefresh() {
    if (autoRefreshTimer) {
        clearInterval(autoRefreshTimer);
        autoRefreshTimer = null;
    }
}

// ========== 页面初始化辅助 ==========
function checkLogin(redirectUrl = 'index.html') {
    const user = getCurrentUser();
    if (!user) {
        showToast('请先登录');
        setTimeout(() => {
            window.location.href = redirectUrl;
        }, 1000);
        return null;
    }
    return user;
}

// ========== 页面专用函数 ==========

// index.html 专用函数
function initIndexPage() {
    let currentUser = null;
    let lastUser = null;
    let refreshTimer = null;

    function updateUserDisplay() {
        const userBtn = document.getElementById('userNowBtn');
        if (currentUser) {
            userBtn.innerHTML = currentUser.length > 10 ? currentUser.substring(0, 8) + '...' : currentUser;
        } else {
            userBtn.innerHTML = '未登录';
        }
    }

    function renderChatList() {
        const container = document.getElementById('chatList');
        if (!currentUser) {
            container.innerHTML = '<div class="empty-state"><span>🔒</span><br>请先登录</div>';
            return;
        }
        
        // 按班级分组
        const groupedChats = getChatsGroupedByClass(currentUser);
        const classNames = Object.keys(groupedChats);
        
        if (classNames.length === 0) {
            container.innerHTML = '<div class="empty-state"><span>💬</span><br>暂无对话<br>点击 + 开始聊天</div>';
            return;
        }
        
        container.innerHTML = '';
        
        // 为每个班级批量获取头像
        const batchRequests = [];
        for (const className of classNames) {
            const chats = groupedChats[className];
            const classIP = getClassIP(className);
            const users = chats.map(c => ({ name: c.name, ip: classIP }));
            batchRequests.push({
                className: className,
                classIP: classIP,
                chats: chats,
                users: users
            });
        }
        
        // 批量获取所有头像数据
        const allAvatarData = {};
        const userList = [];
        for (const req of batchRequests) {
            for (const user of req.users) {
                userList.push(user);
            }
        }
        
        if (userList.length > 0) {
            allAvatarData = batchAvatarRequest(userList);
        }
        
        // 按班级渲染
        for (const className of classNames) {
            const chats = groupedChats[className];
            const classIP = getClassIP(className);
            
            // 添加班级分组标题
            const groupHeader = document.createElement('div');
            groupHeader.className = 'chat-group-header';
            groupHeader.innerHTML = `<span>${escapeHtml(className)}</span>`;
            container.appendChild(groupHeader);
            
            // 添加该班级的所有对话
            for (const chat of chats) {
                const preview = getLastMessagePreview(currentUser, chat);
                const fallbackAvatar = chat.name.charAt(0).toUpperCase();
                
                // 从批量查询结果获取头像
                let avatarUrl = null;
                if (classIP && allAvatarData[classIP]) {
                    avatarUrl = allAvatarData[classIP][chat.name];
                } else if (allAvatarData['local']) {
                    avatarUrl = allAvatarData['local'][chat.name];
                }
                
                const chatItem = document.createElement('div');
                chatItem.className = 'chat-item';
                chatItem.setAttribute('data-user', chat.name);
                chatItem.setAttribute('data-class', chat.className);
                
                // 使用图片头像或首字母备选
                let avatarHtml = '';
                if (avatarUrl) {
                    avatarHtml = `<img src="${escapeHtml(avatarUrl)}" alt="" class="avatar-img" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">`;
                    avatarHtml += `<div class="chat-avatar" style="display:none;">${escapeHtml(fallbackAvatar)}</div>`;
                } else {
                    avatarHtml = `<div class="chat-avatar">${escapeHtml(fallbackAvatar)}</div>`;
                }
                
                chatItem.innerHTML = `
                    ${avatarHtml}
                    <div class="chat-info">
                        <div class="chat-name">${escapeHtml(chat.name)}</div>
                        <div class="chat-preview">${escapeHtml(preview)}</div>
                    </div>
                `;
                
                chatItem.addEventListener('click', () => {
                    window.location.href = `chat.html?class=${encodeURIComponent(chat.className)}&user=${encodeURIComponent(chat.name)}`;
                });
                
                container.appendChild(chatItem);
            }
        }
    }

    function refreshUserData() {
        const newUser = getCurrentUser();
        if (newUser !== lastUser) {
            lastUser = newUser;
            currentUser = newUser;
            updateUserDisplay();
            renderChatList();
        }
    }

    function handleExit() {
        const exitBtn = document.getElementById('exitBtn');
        const registerBtn = document.getElementById('registerBtn');
        const addChatBtn = document.getElementById('addChatBtn');
        const userNowBtn = document.getElementById('userNowBtn');
        
        // 禁用所有相关按钮，防止重复点击
        exitBtn.disabled = true;
        if (registerBtn) registerBtn.disabled = true;
        if (addChatBtn) addChatBtn.disabled = true;
        if (userNowBtn) userNowBtn.disabled = true;
        
        // 添加禁用样式
        exitBtn.style.opacity = '0.6';
        if (registerBtn) registerBtn.style.opacity = '0.6';
        if (addChatBtn) addChatBtn.style.opacity = '0.6';
        if (userNowBtn) userNowBtn.style.opacity = '0.6';
        
        // 显示提示
        showToast('正在退出...', 1500);
        
        // 延迟执行退出脚本，让用户看到提示
        setTimeout(() => {
            try {
                root_cmd("sh /data/local/tmp/schat/5.sh 2>/dev/null");
            } catch(e) {
                console.error('退出脚本执行失败:', e);
            }
            
            // 恢复按钮状态
            setTimeout(() => {
                exitBtn.disabled = false;
                if (registerBtn) registerBtn.disabled = false;
                if (addChatBtn) addChatBtn.disabled = false;
                if (userNowBtn) userNowBtn.disabled = false;
                
                exitBtn.style.opacity = '1';
                if (registerBtn) registerBtn.style.opacity = '1';
                if (addChatBtn) addChatBtn.style.opacity = '1';
                if (userNowBtn) userNowBtn.style.opacity = '1';
                
                // 刷新用户数据，更新界面状态
                refreshUserData();
            }, 0);
        }, 500);
    }

    document.getElementById('userNowBtn').addEventListener('click', () => {
        refreshUserData();
    });
    document.getElementById('exitBtn').addEventListener('click', handleExit);
    document.getElementById('registerBtn').addEventListener('click', () => {
        window.location.href = 'join.html';
    });
    document.getElementById('addChatBtn').addEventListener('click', () => {
        if (!currentUser) {
            showToast('请先登录');
            return;
        }
        window.location.href = 'addchat.html';
    });

    refreshUserData();
    refreshTimer = setInterval(refreshUserData, 1000);

    window.addEventListener('beforeunload', () => {
        if (refreshTimer) clearInterval(refreshTimer);
    });
}
// addchat.html 专用函数
function initAddChatPage() {
    let currentUser = null;
    let classList = [];
    let userList = [];
    let selectedClass = null;
    let selectedClassIP = null;
    let step = 1;

    async function createAndStartChat(otherUser) {
        if (!otherUser || !selectedClass) {
            if (typeof showToast === 'function') showToast('请先选择班级');
            return;
        }
        
        const container = document.getElementById('contentArea');
        const originalHtml = container.innerHTML;
        container.innerHTML = `<div class="loading-state"><div class="loading-spinner"></div><div>正在创建聊天目录...</div></div>`;
        
        const result = createChatDirectory(currentUser, selectedClass, otherUser, selectedClassIP);
        
        if (result.success) {
            if (typeof showToast === 'function') {
                showToast(`✓ 已创建与 ${otherUser} 的对话`, 1500);
            }
            setTimeout(() => {
                window.location.href = `chat.html?class=${encodeURIComponent(selectedClass)}&user=${encodeURIComponent(otherUser)}`;
            }, 500);
        } else {
            container.innerHTML = originalHtml;
            const resetBtn = document.getElementById('resetBtn');
            if (resetBtn) resetBtn.addEventListener('click', resetToClassList);
            document.querySelectorAll('.list-item[data-user]').forEach(item => {
                item.addEventListener('click', () => {
                    const user = item.getAttribute('data-user');
                    createAndStartChat(user);
                });
            });
            
            if (typeof showToast === 'function') {
                showToast(`❌ 创建失败: ${result.error}`, 3000);
            } else {
                alert(`创建失败: ${result.error}`);
            }
        }
    }

    function renderClassList() {
        const container = document.getElementById('contentArea');
        if (classList.length === 0) {
            container.innerHTML = '<div class="empty-state"><span>🏫</span><br>暂无班级列表<br>请检查 devicesIP 文件</div>';
            return;
        }
        let html = '';
        for (const cls of classList) {
            html += `<div class="list-item" data-name="${escapeHtml(cls.name)}" data-ip="${escapeHtml(cls.ip)}">
                <div class="list-avatar">${escapeHtml(cls.name.charAt(0))}</div>
                <div class="list-info">
                    <div class="list-name">${escapeHtml(cls.name)}</div>
                    <div class="list-desc">IP: ${escapeHtml(cls.ip)}</div>
                </div>
            </div>`;
        }
        container.innerHTML = html;
        document.querySelectorAll('.list-item').forEach(item => {
            item.addEventListener('click', () => {
                selectClass(item.getAttribute('data-name'), item.getAttribute('data-ip'));
            });
        });
    }

    async function selectClass(className, ip) {
        selectedClass = className;
        selectedClassIP = ip;
        document.getElementById('step1').classList.add('completed');
        document.getElementById('step2').classList.add('active');
        step = 2;
        
        const container = document.getElementById('contentArea');
        container.innerHTML = `<div class="selected-class">
            <span class="selected-label">当前班级：</span>
            <span class="selected-value">${escapeHtml(selectedClass)}</span>
            <span class="reset-btn" id="resetBtn">重新选择</span>
        </div>
        <div class="loading-state"><div class="loading-spinner"></div><div>正在获取用户列表...</div></div>`;
        
        const resetBtn = document.getElementById('resetBtn');
        if (resetBtn) resetBtn.addEventListener('click', resetToClassList);
        
        const { users, error } = await getRemoteUserListAsync(ip);
        
        if (error) {
            renderError(error);
            return;
        }
        
        userList = (users || []).filter(u => u !== currentUser);
        
        if (userList.length === 0) {
            renderError('该班级暂无其他用户');
        } else {
            renderUserList();
        }
    }

    function renderError(errorMsg) {
        const container = document.getElementById('contentArea');
        container.innerHTML = `<div class="selected-class">
            <span class="selected-label">当前班级：</span>
            <span class="selected-value">${escapeHtml(selectedClass)}</span>
            <span class="reset-btn" id="resetBtn">重新选择</span>
        </div>
        <div class="empty-state" style="color:#e74c3c;">
            <span>❌</span><br>
            获取用户列表失败<br>
            <div style="font-size:12px;color:#555;background:#f5f5f5;padding:8px;margin-top:12px;border-radius:6px;text-align:left;word-break:break-all;max-width:90%;margin-left:auto;margin-right:auto;">
                ${escapeHtml(errorMsg)}
            </div>
            <button id="retryBtn" style="margin-top:16px;padding:8px 20px;background:#667eea;color:white;border:none;border-radius:20px;">重试</button>
        </div>`;
        const resetBtn = document.getElementById('resetBtn');
        if (resetBtn) resetBtn.addEventListener('click', resetToClassList);
        const retryBtn = document.getElementById('retryBtn');
        if (retryBtn) retryBtn.addEventListener('click', () => selectClass(selectedClass, selectedClassIP));
    }

    function renderUserList() {
        const container = document.getElementById('contentArea');
        
        let html = `<div class="selected-class">
            <span class="selected-label">当前班级：</span>
            <span class="selected-value">${escapeHtml(selectedClass)}</span>
            <span class="reset-btn" id="resetBtn">重新选择</span>
        </div>`;
        
        // 批量获取该班级所有用户的头像
        const batchUsers = userList.map(u => ({ name: u, ip: selectedClassIP }));
        const avatarDataByIp = batchAvatarRequest(batchUsers);
        const avatarData = avatarDataByIp[selectedClassIP] || avatarDataByIp['local'] || {};
        
        for (const user of userList) {
            const avatarUrl = avatarData[user];
            const fallbackAvatar = user.charAt(0);
            
            // 使用图片头像或首字母备选
            let avatarHtml = '';
            if (avatarUrl) {
                avatarHtml = `<img src="${escapeHtml(avatarUrl)}" alt="" class="avatar-img" onerror="this.style.display='none'; this.parentElement.querySelector('.list-avatar-fallback').style.display='flex';">`;
                avatarHtml += `<div class="list-avatar list-avatar-fallback" style="display:none;">${escapeHtml(fallbackAvatar)}</div>`;
            } else {
                avatarHtml = `<div class="list-avatar">${escapeHtml(fallbackAvatar)}</div>`;
            }
            
            html += `<div class="list-item" data-user="${escapeHtml(user)}">
                ${avatarHtml}
                <div class="list-info">
                    <div class="list-name">${escapeHtml(user)}</div>
                </div>
            </div>`;
        }
        container.innerHTML = html;
        const resetBtn = document.getElementById('resetBtn');
        if (resetBtn) resetBtn.addEventListener('click', resetToClassList);
        
        document.querySelectorAll('.list-item[data-user]').forEach(item => {
            item.addEventListener('click', () => {
                const otherUser = item.getAttribute('data-user');
                createAndStartChat(otherUser);
            });
        });
    }

    function resetToClassList() {
        step = 1;
        selectedClass = null;
        selectedClassIP = null;
        userList = [];
        document.getElementById('step1').classList.remove('completed', 'active');
        document.getElementById('step2').classList.remove('active', 'completed');
        document.getElementById('step1').classList.add('active');
        loadClassList();
    }

    function loadClassList() {
        const container = document.getElementById('contentArea');
        container.innerHTML = '<div class="loading-state"><div class="loading-spinner"></div><div>加载班级列表...</div></div>';
        setTimeout(() => {
            classList = getClassList();
            renderClassList();
        }, 50);
    }

    function init() {
        currentUser = getCurrentUser();
        if (!currentUser) {
            document.getElementById('contentArea').innerHTML = `<div class="empty-state">
                <span>🔒</span><br>请先登录<br><button id="goLoginBtn" style="margin-top:16px;padding:8px 20px;background:#667eea;color:white;border:none;border-radius:20px;">去登录</button>
            </div>`;
            const goLoginBtn = document.getElementById('goLoginBtn');
            if (goLoginBtn) goLoginBtn.addEventListener('click', () => { window.location.href = 'index.html'; });
            return;
        }
        loadClassList();
    }

    document.getElementById('backBtn').addEventListener('click', () => {
        if (step === 2) resetToClassList();
        else if (typeof goBack === 'function') goBack('index.html');
        else window.location.href = 'index.html';
    });
    
    init();
}

// chat.html 专用函数
function initChatPage() {
    let currentUser = null;
    let otherUser = null;
    let currentClass = null;
    let messageList = [];
    let sendLock = false;  // 防止重复发送

    // 辅助函数：滚动到底部
    function scrollToBottom() {
        const container = document.getElementById('messagesContainer');
        if (container) {
            setTimeout(() => {
                container.scrollTop = container.scrollHeight;
            }, 50);
        }
    }

    // 应用动画到新添加的消息元素
    function applyAnimationToMessage(element, animationClass) {
        if (element && animationClass) {
            element.classList.add(animationClass);
            setTimeout(() => {
                element.classList.remove(animationClass);
            }, 400);
        }
    }

    // 创建消息DOM元素（不添加到容器）
    function createMessageElement(msg, isPending = false) {
        const msgDiv = document.createElement('div');
        const msgClass = msg.isSelf ? 'message-self' : 'message-other';
        msgDiv.className = `message ${msgClass}`;
        
        let innerHtml = `<div class="message-content">`;
        if (!msg.isSelf) {
            innerHtml += `<div class="message-sender">${escapeHtml(msg.sender)}</div>`;
        }
        innerHtml += `<div class="message-bubble">${escapeHtml(msg.displayContent)}</div>`;
        innerHtml += `<div class="message-time">${msg.displayTime || '发送中...'}</div>`;
        innerHtml += `</div>`;
        msgDiv.innerHTML = innerHtml;
        
        return msgDiv;
    }

    // 渲染消息列表（完整渲染）
    function renderMessages() {
        const container = document.getElementById('messagesContainer');
        if (!currentUser) {
            container.innerHTML = '<div class="empty-state"><span>🔒</span><br>请先登录</div>';
            return;
        }
        if (!currentClass) {
            container.innerHTML = '<div class="empty-state"><span>🏫</span><br>班级信息缺失</div>';
            return;
        }
        if (!otherUser) {
            container.innerHTML = '<div class="empty-state"><span>💬</span><br>选择聊天对象</div>';
            return;
        }
        
        const messages = loadMessages(currentUser, currentClass, otherUser);
        messageList = messages;
        
        if (messages.length === 0) {
            container.innerHTML = '<div class="empty-state"><span>💬</span><br>暂无消息<br>发送第一条消息吧~</div>';
            return;
        }
        
        let html = '';
        for (const msg of messages) {
            const msgClass = msg.isSelf ? 'message-self' : 'message-other';
            html += `<div class="message ${msgClass}">
                <div class="message-content">
                    ${!msg.isSelf ? `<div class="message-sender">${escapeHtml(msg.sender)}</div>` : ''}
                    <div class="message-bubble">${escapeHtml(msg.displayContent)}</div>
                    <div class="message-time">${msg.displayTime}</div>
                </div>
            </div>`;
        }
        container.innerHTML = html;
        scrollToBottom();
    }

    // 增量添加新消息（带动画）
    function appendMessage(msg) {
        const container = document.getElementById('messagesContainer');
        if (!container) return;
        
        // 移除空状态提示
        if (container.querySelector('.empty-state')) {
            renderMessages();
            return;
        }
        
        const msgClass = msg.isSelf ? 'message-self' : 'message-other';
        const msgDiv = document.createElement('div');
        msgDiv.className = `message ${msgClass}`;
        msgDiv.innerHTML = `
            <div class="message-content">
                ${!msg.isSelf ? `<div class="message-sender">${escapeHtml(msg.sender)}</div>` : ''}
                <div class="message-bubble">${escapeHtml(msg.displayContent)}</div>
                <div class="message-time">${msg.displayTime}</div>
            </div>
        `;
        
        container.appendChild(msgDiv);
        
        // 添加动画
        if (msg.isSelf) {
            applyAnimationToMessage(msgDiv, 'message-sent');
        } else {
            applyAnimationToMessage(msgDiv, 'message-new');
        }
        
        scrollToBottom();
    }

    // 发送消息（带动画和状态管理）
    async function handleSendMessage() {
        if (sendLock) {
            showToast('正在发送中，请稍候...', 1000);
            return;
        }
        
        const inputEl = document.getElementById('msgInput');
        const content = inputEl.value.trim();
        
        if (!content) {
            showToast('请输入消息内容');
            return;
        }
        
        // 锁定发送按钮
        sendLock = true;
        const sendBtn = document.getElementById('sendBtn');
        const originalBtnText = sendBtn.innerHTML;
        sendBtn.innerHTML = '发送中...';
        sendBtn.classList.add('send-btn-sending');
        
        // 创建临时消息对象
        const tempTimestamp = Date.now().toString();
        const tempMsg = {
            sender: currentUser,
            type: '0',
            content: content,
            displayContent: content,
            timestamp: tempTimestamp,
            displayTime: '发送中...',
            isSelf: true,
            isPending: true
        };
        
        // 创建临时消息元素并添加发送中动画
        const container = document.getElementById('messagesContainer');
        const isEmpty = container.querySelector('.empty-state');
        
        let tempMsgDiv = null;
        if (isEmpty) {
            renderMessages();
            tempMsgDiv = container.querySelector('.message-self:last-child');
            if (tempMsgDiv) {
                tempMsgDiv.classList.add('message-sending');
            }
        } else {
            tempMsgDiv = createMessageElement(tempMsg);
            container.appendChild(tempMsgDiv);
            applyAnimationToMessage(tempMsgDiv, 'message-sent');
            tempMsgDiv.classList.add('message-sending');
            scrollToBottom();
        }
        
        // 清空输入框
        inputEl.value = '';
        
        // 调用发送接口
        const result = sendTextMessage(currentUser, currentClass, otherUser, content);
        
        // 移除发送中动画
        if (tempMsgDiv) {
            tempMsgDiv.classList.remove('message-sending');
        }
        
        if (result.success) {
            // 发送成功，刷新消息列表（从文件重新加载，获取正确的timestamp）
            const newMessages = loadMessages(currentUser, currentClass, otherUser);
            messageList = newMessages;
            
            // 找到刚发送的消息（最新的自己发送的消息）
            const sentMsg = newMessages.filter(m => m.isSelf).pop();
            if (sentMsg && tempMsgDiv) {
                // 更新临时消息元素的时间和内容
                const timeEl = tempMsgDiv.querySelector('.message-time');
                if (timeEl) timeEl.textContent = sentMsg.displayTime;
                // 确保显示正确的内容
                const bubbleEl = tempMsgDiv.querySelector('.message-bubble');
                if (bubbleEl) bubbleEl.textContent = sentMsg.displayContent;
                // 移除发送中类，添加成功动画
                tempMsgDiv.classList.remove('message-sending');
                applyAnimationToMessage(tempMsgDiv, 'message-sent');
            } else {
                // 如果找不到，重新渲染整个列表
                renderMessages();
            }
            showToast('发送成功', 1000);
        } else {
            // 发送失败
            if (tempMsgDiv) {
                tempMsgDiv.classList.add('message-failed');
                // 添加重试按钮到消息气泡
                const bubbleEl = tempMsgDiv.querySelector('.message-bubble');
                if (bubbleEl && !bubbleEl.querySelector('.retry-btn')) {
                    const originalContent = bubbleEl.innerHTML;
                    bubbleEl.innerHTML = `${originalContent}<button class="retry-btn" style="margin-left:12px;background:rgba(255,255,255,0.3);border:none;border-radius:20px;padding:4px 12px;color:white;font-size:24px;">重试</button>`;
                    const retryBtn = bubbleEl.querySelector('.retry-btn');
                    if (retryBtn) {
                        retryBtn.addEventListener('click', (e) => {
                            e.stopPropagation();
                            // 重新发送
                            inputEl.value = content;
                            tempMsgDiv.remove();
                            sendLock = false;
                            handleSendMessage();
                        });
                    }
                }
            } else {
                renderMessages();
            }
            showToast(`发送失败: ${result.error}`, 3000);
        }
        
        // 恢复按钮状态
        sendLock = false;
        sendBtn.innerHTML = originalBtnText;
        sendBtn.classList.remove('send-btn-sending');
        
        // 聚焦输入框
        inputEl.focus();
    }

    // 刷新聊天（检查新消息）
    function refreshChat() {
        if (!currentUser || !otherUser || !currentClass) return;
        
        const newMessages = loadMessages(currentUser, currentClass, otherUser);
        
        if (newMessages.length !== messageList.length) {
            // 有新消息，找出新增的消息
            const oldTimestamps = new Set(messageList.map(m => m.timestamp));
            const newMsgs = newMessages.filter(m => !oldTimestamps.has(m.timestamp));
            
            messageList = newMessages;
            
            if (newMsgs.length > 0) {
                // 逐个添加新消息带动画
                for (const msg of newMsgs) {
                    appendMessage(msg);
                }
            } else {
                // 其他变化（如时间戳更新），重新渲染
                renderMessages();
            }
        } else {
            // 检查消息内容是否有变化（如时间显示更新）
            let needRender = false;
            for (let i = 0; i < newMessages.length; i++) {
                if (newMessages[i].displayTime !== messageList[i]?.displayTime ||
                    newMessages[i].displayContent !== messageList[i]?.displayContent) {
                    needRender = true;
                    break;
                }
            }
            if (needRender) {
                messageList = newMessages;
                renderMessages();
            }
        }
    }

    function init() {
        otherUser = getUrlParam('user');
        currentClass = getUrlParam('class');
        currentUser = getCurrentUser();
        
        if (!currentUser) {
            document.getElementById('chatTitle').innerHTML = '未登录';
            showToast('请先登录');
            setTimeout(() => { window.location.href = 'index.html'; }, 1500);
            return;
        }
        if (!currentClass) {
            document.getElementById('chatTitle').innerHTML = '班级信息缺失';
            return;
        }
        if (!otherUser) {
            document.getElementById('chatTitle').innerHTML = '请选择聊天对象';
            return;
        }
        
        document.getElementById('chatTitle').innerHTML = `${escapeHtml(otherUser)} <span class="class-badge">(${escapeHtml(currentClass)})</span>`;
        renderMessages();
        startAutoRefresh(() => {
            if (currentUser && otherUser && currentClass) {
                refreshChat();
            }
        }, 2000);
    }

    document.getElementById('backBtn').addEventListener('click', () => {
        stopAutoRefresh();
        goBack('index.html');
    });
    document.getElementById('refreshBtn').addEventListener('click', refreshChat);
    document.getElementById('sendBtn').addEventListener('click', handleSendMessage);
    document.getElementById('msgInput').addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            handleSendMessage();
        }
    });
    
    window.addEventListener('beforeunload', () => stopAutoRefresh());
    
    init();
}

// join.html 专用函数
function initJoinPage() {
    function updateUI() {
        const raw = document.getElementById('username').value;
        const name = raw.trim().replace(/[\n\r]/g, '');
        const length = name.length;
        const previewDiv = document.getElementById('namePreview');
        const hintDiv = document.getElementById('hintText');
        const indicator = document.getElementById('lengthIndicator');
        
        indicator.textContent = `字数：${length}/4`;
        indicator.style.color = (length >= 2 && length <= 4) ? '#2b8a3e' : '#adb5bd';
        
        if (name === '') {
            previewDiv.innerHTML = '输入后显示预览 →';
            hintDiv.innerHTML = '';
            return;
        }
        
        if (isValidChineseName(name)) {
            previewDiv.innerHTML = `✅ 当前输入：<span>${escapeHtml(name)}</span>`;
            hintDiv.innerHTML = '✓ 姓名格式正确（2-4个汉字）';
            hintDiv.style.color = '#2b8a3e';
        } else {
            if (length < 2) hintDiv.innerHTML = '✗ 姓名至少需要2个汉字';
            else if (length > 4) hintDiv.innerHTML = '✗ 姓名不能超过4个汉字';
            else hintDiv.innerHTML = '✗ 请输入纯中文姓名';
            hintDiv.style.color = '#fa5252';
            previewDiv.innerHTML = `⚠️ 当前输入：<span style="color:#e03131">${escapeHtml(name)}</span>`;
        }
    }

    function restrictToChinese(e) {
        const input = e.target;
        const chineseOnly = input.value.replace(/[^\u4e00-\u9fa5]/g, '');
        if (input.value !== chineseOnly) input.value = chineseOnly;
        updateUI();
    }

    function doRegister() {
        const name = document.getElementById('username').value.trim();
        if (!isValidChineseName(name)) {
            if (name.length < 2) showStatus('status', '姓名至少需要2个汉字', 'error');
            else if (name.length > 4) showStatus('status', '姓名不能超过4个汉字', 'error');
            else showStatus('status', '请输入纯中文姓名', 'error');
            return;
        }
        
        const registerBtn = document.getElementById('registerBtn');
        const backBtn = document.getElementById('backBtn');
        
        registerBtn.disabled = true;
        backBtn.disabled = true;
        hideStatus('status');
        showStatus('status', '正在注册，请稍候...', 'loading');
        
        const result = registerUser(name);
        
        registerBtn.disabled = false;
        backBtn.disabled = false;
        
        if (result.success) {
            showStatus('status', `✅ ${result.message}`, 'success');
            setTimeout(() => { window.location.href = 'index.html'; }, 1500);
        } else {
            showStatus('status', result.message, 'error');
        }
    }

    const usernameInput = document.getElementById('username');
    usernameInput.addEventListener('input', restrictToChinese);
    usernameInput.addEventListener('keyup', updateUI);
    document.getElementById('registerBtn').addEventListener('click', doRegister);
    document.getElementById('backBtn').addEventListener('click', () => goBack('index.html'));
    usernameInput.addEventListener('keypress', (e) => { if (e.key === 'Enter') doRegister(); });
    
    updateUI();
}