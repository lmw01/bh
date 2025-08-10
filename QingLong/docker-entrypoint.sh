#!/bin/bash

# ▼▼▼▼▼▼▼▼▼▼▼▼ 新增：设置默认值 ▼▼▼▼▼▼▼▼▼▼▼▼
DEFAULT_ADMIN_USERNAME="admin"
DEFAULT_ADMIN_PASSWORD="admin.0"
DEFAULT_RCLONE_CONF="[huggingface]
type = webdav
url = https://zeze.teracloud.jp/dav/
user = lmw01
pass = VIIQjg3t8MsgYm0uGW84eQ1ognBzmwh5ROXtzy8qNhc"
# 下面通知 可不修改只是不推送
DEFAULT_NOTIFY_CONFIG='{
  "type": "weWorkBot",
  "weWorkBotKey": "323eef9d-844a-404f-a0f3-4cff47966666"
}'

# 使用环境变量或默认值
ADMIN_USERNAME="${ADMIN_USERNAME:-$DEFAULT_ADMIN_USERNAME}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-$DEFAULT_ADMIN_PASSWORD}"
RCLONE_CONF="${RCLONE_CONF:-$DEFAULT_RCLONE_CONF}"
NOTIFY_CONFIG="${NOTIFY_CONFIG:-$DEFAULT_NOTIFY_CONFIG}"
# ▲▲▲▲▲▲▲▲▲▲▲▲ 新增结束 ▲▲▲▲▲▲▲▲▲▲▲▲

# ▼▼▼▼▼▼▼▼▼▼▼▼ 以下为您的原始脚本（完全不变） ▼▼▼▼▼▼▼▼▼▼▼▼
dir_shell=/ql/shell
. $dir_shell/share.sh
. $dir_shell/env.sh

echo -e "======================写入rclone配置========================\n"
echo "$RCLONE_CONF" > ~/.config/rclone/rclone.conf

echo -e "======================1. 检测配置文件========================\n"
import_config "$@"
make_dir /etc/nginx/conf.d
make_dir /run/nginx
init_nginx
fix_config

pm2 l &>/dev/null

echo -e "======================2. 安装依赖========================\n"
patch_version

echo -e "======================3. 启动nginx========================\n"
nginx -s reload 2>/dev/null || nginx -c /etc/nginx/nginx.conf
echo -e "nginx启动成功...\n"

echo -e "======================4. 启动pm2服务========================\n"
reload_update
reload_pm2

if [[ $AutoStartBot == true ]]; then
  echo -e "======================5. 启动bot========================\n"
  nohup ql bot >$dir_log/bot.log 2>&1 &
  echo -e "bot后台启动中...\n"
fi

if [[ $EnableExtraShell == true ]]; then
  echo -e "====================6. 执行自定义脚本========================\n"
  nohup ql extra >$dir_log/extra.log 2>&1 &
  echo -e "自定义脚本后台执行中...\n"
fi

echo -e "############################################################\n"
echo -e "容器启动成功..."
echo -e "############################################################\n"

echo -e "##########写入登陆信息############"
dir_root=/ql && source /ql/shell/api.sh 
init_auth_info() {
  local body="$1"
  local tip="$2"
  local currentTimeStamp=$(date +%s)
  local api=$(
    curl -s --noproxy "*" "http://0.0.0.0:5600/api/user/init?t=$currentTimeStamp" \
      -X 'PUT' \
      -H "Accept: application/json" \
      -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 11_2_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.90 Safari/537.36" \
      -H "Content-Type: application/json;charset=UTF-8" \
      -H "Origin: http://0.0.0.0:5700" \
      -H "Referer: http://0.0.0.0:5700/crontab" \
      -H "Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7" \
      --data-raw "{$body}" \
      --compressed
  )
  code=$(echo "$api" | jq -r .code)
  message=$(echo "$api" | jq -r .message)
  if [[ $code == 200 ]]; then
    echo -e "${tip}成功🎉"
  else
    echo -e "${tip}失败(${message})"
  fi
}

init_auth_info "\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"" "Change Password"

if [ -n "$RCLONE_CONF" ]; then
  echo -e "##########同步备份############"
  REMOTE_FOLDER="${RCLONE_REMOTE_PATH:-huggingface:/qinglong}"
  echo "[DEBUG] 同步路径：$REMOTE_FOLDER"

  OUTPUT=$(rclone ls "$REMOTE_FOLDER" 2>&1)
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ]; then
    if [ -z "$OUTPUT" ]; then
      echo "初次安装"
    else
      mkdir /ql/.tmp/data
      echo "[DEBUG] 开始同步..."
      rclone sync $REMOTE_FOLDER /ql/.tmp/data && real_time=true ql reload data
    fi
  elif [[ "$OUTPUT" == *"directory not found"* ]]; then
    echo "错误：文件夹不存在"
  else
    echo "错误：$OUTPUT"
  fi
else
    echo "没有检测到Rclone配置信息"
fi

if [ -n "$NOTIFY_CONFIG" ]; then
    # 写入通知配置（关键修复）
    echo "$NOTIFY_CONFIG" > /ql/data/config/notify.json
    
    # 提取路径名称（兼容各种格式）
    REMOTE_NAME=$(echo "${RCLONE_REMOTE_PATH:-huggingface:/qinglong}" | 
                 awk -F':' '{print $2}' | 
                 sed 's:^/*::; s:/.*$::')
    REMOTE_NAME=${REMOTE_NAME:-qinglong}

    # 加载通知API
    dir_root=/ql && source /ql/shell/api.sh
    
    # 发送通知（带错误重试）
    for i in {1..3}; do
        if notify_api "${REMOTE_NAME}服务启动" \
                      "🟢 节点: ${REMOTE_NAME}\n⏰ 时间: $(date +'%m-%d %H:%M')\n${RCLONE_REMOTE_PATH}"; then
            break
        else
            sleep 2
        fi
    done
fi

export PASSWORD=$ADMIN_PASSWORD
code-server --bind-addr 0.0.0.0:7860 --port 7860

tail -f /dev/null

exec "$@"
