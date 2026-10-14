# llama-server 关键参数速查

基准命令结构（Windows bat 用 `^` 续行）：

```bat
llama-server.exe -m models\<model>.gguf ^
  --host 127.0.0.1 --port 8085 ^
  -c 102400 ^
  --cache-type-k q4_0 --cache-type-v q4_0 ^
  --jinja ^
  [--mmproj models\mmproj-<x>.gguf --no-mmproj-offload] ^
  [--spec-type draft-mtp --spec-draft-n-max 2] ^
  [--no-reasoning-preserve]
```

## 参数表

| 参数 | 作用 | 建议值（16GB 卡） |
| --- | --- | --- |
| `-m <path>` | 模型路径（相对 llama-server.exe 所在目录） | `models\xxx.gguf` |
| `--mmproj <path>` | 视觉塔路径（多模态必需） | `models\mmproj-xxx.gguf` |
| `--host / --port` | 监听地址/端口 | `127.0.0.1` / `8085` |
| `-c <n>` | 上下文长度（token） | 100K=102400（甜点）；128K=131072；不要 200K |
| `--cache-type-k/v <t>` | KV 缓存量化省显存 | `q4_0`（上下文内存减半，质量损失小） |
| `--jinja` | 使用模型的 jinja 聊天模板（Qwen3 必需，否则格式错乱） | 固定开 |
| `--no-mmproj-offload` | 视觉塔留在 CPU，不占显存 | 显存紧张时开 |
| `--spec-type draft-mtp` | MTP 投机采样加速 | 上下文 ≤100K 时开 |
| `--spec-draft-n-max <n>` | 草稿 token 数 | `2` |
| `--no-reasoning-preserve` | 关闭思考（reasoning）输出 | 快速版开；追求深度推理时关 |
| `-ngl <n>` | GPU 层数（默认全量） | 默认即可；爆显存时降低并配 `-nmm` |
| `-t <n>` | CPU 线程（仅 CPU 部分） | 默认自动 |
| `--fit-target <MB>` | 按显存自适应（0=禁用） | 显存紧张时可设 1024 |

## 思考（reasoning）行为

- Qwen3.8 默认输出思考内容，`--no-reasoning-preserve` 关闭。
- 无思考版好处：输出更快 + 思考 token 不进对话历史（省上下文/省 KV）。
- 两个版本用同一端口切换即可，客户端（Harness）无需改配置。

## 服务管理（Windows）

```bat
:: 停止（结束所有 llama-server 实例）
taskkill /IM llama-server.exe /F

:: 健康检查
curl http://127.0.0.1:8085/health

:: 看进程与显存
tasklist | findstr llama-server
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

## 关键约束

- **bat 文件必须 GBK 编码 + CRLF 行尾**（UTF-8/LF 会导致中文拆碎、echo/exit/pause 命令错乱）。
- 防重复启动：脚本开头用 `tasklist | findstr llama-server` 检测，已在运行则提示退出（第二实例必 OOM）。
- 显存看"空闲时 3–4GB"属 llama.cpp 惰性提交，属正常；请求时才满载。
- OpenAI 兼容端点：`http://127.0.0.1:<port>/v1`（chat/completions、models）。
