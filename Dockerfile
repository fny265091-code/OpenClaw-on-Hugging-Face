FROM node:22-slim

# 1. 基础系统依赖
# 保留 psmisc (用于 fuser), procps (用于 pkill), iproute2 (用于网路诊断)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssh-client build-essential python3 python3-pip \
    g++ make ca-certificates curl iptables \
    psmisc netcat-openbsd lsof iproute2 \
    procps && \
    rm -rf /var/lib/apt/lists/*

# 2. 安装 Tailscale & OpenClaw
RUN curl -fsSL https://tailscale.com/install.sh | sh
RUN npm install -g openclaw@latest --unsafe-perm

# 3. 安装 Python 核心依赖 (用于 sync.py 的备份还原)
RUN pip3 install --no-cache-dir --break-system-packages \
    --upgrade huggingface_hub \
    "httpx[socks]" \
    "requests[socks]" \
    PySocks

# 4. 工作目录与文件拷贝
WORKDIR /app
COPY sync.py .
COPY start-openclaw.sh .

# 5. 权限与目录准备
# 确保 root 目录下 .openclaw 文件夹存在且有权限，防止配置生成失败
RUN chmod +x start-openclaw.sh && \
    mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale /root/.openclaw && \
    chmod -R 777 /var/run/tailscale /var/cache/tailscale /var/lib/tailscale /root/.openclaw

# 6. 环境配置
# 7860 是 Hugging Face Space 的默认暴露端口
ENV PORT=7860
ENV HOME=/root

EXPOSE 7860

# 7. 启动
CMD ["/bin/bash", "./start-openclaw.sh"]
