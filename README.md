<img width="778" height="344" alt="image" src="https://github.com/user-attachments/assets/b04a9cb6-d7d3-4d72-8296-7ca02272775d" />这是一个专门为 Hugging Face Spaces 设计的部署方案，集成了 OpenClaw 智能网关，并通过 Tailscale 实现动态出口节点（Exit Node）切换，以解决 API 访问配额限制及网络地域问题。

🌟 核心功能
自动出口节点切换：动态监测指定的 Tailscale 节点（PC、手机、工作机）状态。若首选节点在线，自动切换出口流量，实现 IP 漂移。

模型配额超限保护：实时监控 OpenClaw 日志。一旦触发 429 Quota Exceeded 错误，脚本会自动清理进程、更换模型并重启。

用户态网络栈：在无 root 权限的容器环境下，利用 Tailscale 的 userspace-networking 和 SOCKS5 代理确保网络连通性。

自动备份与恢复：启动时自动从指定的 Hugging Face 仓库恢复配置文件，运行中每 10 分钟自动备份最新的数据。

🛠️ 环境要求
在部署到 Hugging Face Spaces 之前，请确保已准备好以下机密（Secrets）：
变量名,说明
TS_AUTHKEY,Tailscale 的 Auth Key（建议设置为永不过期）
OPENAI_API_KEY,你的模型提供商 API Key
API_BASE,API 的基础地址
MODEL,模型列表，用分号分隔（例如 model1;model2）
OPENCLAW_GATEWAY_PASSWORD,OpenClaw 管理面板的访问令牌
🚀 脚本架构说明
程序主要由 start.sh (或你的启动脚本) 驱动，包含以下几个并行模块：

1. Tailscale 守护模块
在用户态启动 Tailscale，开放 localhost:1055 作为 SOCKS5 代理。

Bash
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
2. 动态 IP 监控逻辑
脚本会按照 PC > 手机 > 远程主机 的优先级，每 60 秒检查一次节点在线状态。

3. OpenClaw 运行循环
主进程负责生成 openclaw.json 配置，并实时解析日志：

监控：使用 grep 捕捉 "exceeded today's quota" 关键字。

热切换：发现配额用尽后，自动根据 MODEL 环境变量中的顺序切换到下一个模型。

📂 项目结构
Plaintext
.
├── start-openclaw.sh              # 核心启动与监控脚本
├── sync.py               # 负责与 GitHub/HF 仓库同步备份的工具
├── Dockerfile            # 容器定义

⚠️ 注意事项
节点授权：请务必在 Tailscale 控制面板中手动将你的 PC/手机设置为 "Run as Exit Node"，并关闭关键节点的 Key Expiry。

存储空间：Hugging Face 的本地存储是临时性的。请确保 sync.py 正常工作，以便将数据持久化到你的 Private Dataset 或 Repository。

网络安全：OpenClaw 已配置为本地模式并开启 Token 校验，但请勿泄露你的网关密码。

📜 许可证
本项目基于 MIT 协议开源。请遵守相关 AI 模型提供商的使用条例。

如何使用？
在 Hugging Face 上创建一个新的 Space (选择 Docker 模板)。

将你的代码上传至仓库。

在 Settings -> Variables and secrets 中配置上述所有环境变量。

保存并等待自动构建。
