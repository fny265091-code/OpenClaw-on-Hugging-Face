#!/bin/bash

# --- [1. Tailscale 基础启动] ---
echo "Starting Tailscale in userspace mode..."
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
tailscale up --authkey="${TS_AUTHKEY}" \
             --hostname=hf-openclaw \
             --accept-dns=false \
             --reset

# --- [2. 动态出口节点监测] ---
PC_NODE="..."
PHONE_NODE="..."
WORK_PC_NODE="..."

cat > /tmp/node_monitor.sh <<EOF
#!/bin/bash
sleep 300
while true; do
    STATUS_DATA=\$(tailscale status)
    CURRENT_EXIT_LINE=\$(echo "\$STATUS_DATA" | grep "exit node")
    TARGET_NODE=""
    if echo "\$STATUS_DATA" | grep "$PC_NODE" | grep -qv "offline"; then
        TARGET_NODE="$PC_NODE"
    elif echo "\$STATUS_DATA" | grep "$PHONE_NODE" | grep -qv "offline"; then
        TARGET_NODE="$PHONE_NODE"
    elif echo "\$STATUS_DATA" | grep "$WORK_PC_NODE" | grep -qv "offline"; then
        TARGET_NODE="$WORK_PC_NODE"
    fi
    if [ -n "\$TARGET_NODE" ]; then
        if [[ ! "\$CURRENT_EXIT_LINE" =~ "\$TARGET_NODE" ]]; then
            tailscale set --exit-node=\$TARGET_NODE --exit-node-allow-lan-access=true
        fi
    else
        if [ ! -z "\$CURRENT_EXIT_LINE" ]; then
            tailscale set --exit-node=
        fi
    fi
    sleep 60
done
EOF

chmod +x /tmp/node_monitor.sh
/tmp/node_monitor.sh &

# --- [3. 环境配置与恢复] ---
export ALL_PROXY=socks5h://localhost:1055
mkdir -p /root/.openclaw
python3 /app/sync.py restore

# --- [4. 环境准备与依赖安装] ---
# 注意：原版不需要在脚本里运行 npm install http-proxy，因为不使用 Node.js 转发
apt-get update && apt-get install -y psmisc

# --- [5. 模型配置生成逻辑] ---
IFS=';' read -ra MODEL_ARRAY <<< "$MODEL"
CURRENT_INDEX=0
TOTAL_MODELS=${#MODEL_ARRAY[@]}

generate_config() {
    local raw_model=${MODEL_ARRAY[$CURRENT_INDEX]}
    local target_model=$(echo "$raw_model" | xargs | tr -d '"' | tr -d "'" | \
        sed 's/^modelscope://g' | \
        sed 's/^openai://g' | \
        sed 's|^qwen/|Qwen/|g')

    cat > /root/.openclaw/openclaw.json <<EOF
{
  "models": {
    "providers": {
      "modelscope": {
        "baseUrl": "$API_BASE",
        "apiKey": "$OPENAI_API_KEY",
        "api": "openai-completions",
        "models": [{ "id": "$target_model", "name": "$target_model" }]
      }
    }
  },
  "agents": {
    "defaults": { 
      "model": { "primary": "modelscope/$target_model" }
    }
  },
  "gateway": {
    "mode": "local",
    "auth": { "mode": "token", "token": "$OPENCLAW_GATEWAY_PASSWORD" },
    "controlUi": { 
      "enabled": true, 
      "allowInsecureAuth": true, 
      "dangerouslyDisableDeviceAuth": true, 
      "dangerouslyAllowHostHeaderOriginFallback": true 
    }
  }
}
EOF
}

# --- [6. 启动 OpenClaw 控制循环 (前台守卫进程)] ---
# 注意：原版将 OpenClaw 绑定在 7860 端口，作为主进程运行
while true; do
    # 清理旧进程
    fuser -k 7860/tcp >/dev/null 2>&1 || true
    pkill -9 -x openclaw >/dev/null 2>&1 || true
    sleep 2
    
    generate_config
    
    echo "[Runtime] Starting OpenClaw on port 7860..."
    LOG_FILE="/tmp/openclaw.log"
    > "$LOG_FILE"
    
    # 直接在 7860 启动 OpenClaw
    stdbuf -oL openclaw gateway run --bind lan --port 7860 2>&1 | tee -a "$LOG_FILE" &
    OC_PID=$!

    # 监控配额超限
    while kill -0 $OC_PID 2>/dev/null; do
        if grep -qi "exceeded today's quota" "$LOG_FILE"; then
            kill -9 $OC_PID
            TOUCH_QUOTA=true
            break
        fi
        sleep 5
    done

    # 切换模型逻辑
    if [ "$TOUCH_QUOTA" = true ]; then
        CURRENT_INDEX=$((CURRENT_INDEX + 1))
        unset TOUCH_QUOTA
        if [ $CURRENT_INDEX -ge $TOTAL_MODELS ]; then
            CURRENT_INDEX=0
            echo "[Quota] All models exhausted. Sleeping for 1 hour..."
            sleep 3600
        fi
    fi
    sleep 2
done &

# --- [7. 定期备份循环 (后台运行)] ---
(while true; do sleep 600; python3 /app/sync.py backup; done) &

