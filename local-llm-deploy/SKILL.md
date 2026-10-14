---
name: local-llm-deploy
description: 本地 GGUF 大模型部署与调优（llama.cpp 系）。当用户需要本地部署大模型、下载/校验 GGUF 模型、写 llama-server 启动脚本、模型跑得慢/爆显存/上下文不够、切换量化档位、把本地模型接入 OpenAI 兼容客户端（如 DeepSeek Harness）或排查本地推理服务报错（OOM、GGML_ASSERT、上下文截断、bat 乱码等）时使用。触发场景：用户说"部署 XX 模型""下载模型""模型太慢""显存不够""上下文不够""接入 Harness""本地模型不能看图""启动脚本怎么写"等。
---

# 本地大模型部署（llama.cpp 路线）

## 意图路由

| 用户目标 | 默认动作 |
| --- | --- |
| 部署新模型（下载→启动→接入） | 按"部署流程"完整走一遍 |
| 模型跑得慢 / 提速 | 先查显存与实测速度，按"调优"节处理 |
| 爆显存 / OOM / GGML_ASSERT | 读 references/troubleshooting.md，按表处置 |
| 上下文不够 / 截断 | 调整 `-c` 与 KV 量化，见参数表 |
| 接入 Agent 框架（Harness） | 读 references/harness-integration.md |
| 本地模型不能发图/看图 | 检查 harness 多模态声明，见 harness-integration.md |
| 生成/修改启动脚本 | 用 scripts/gen_start_bat.ps1 |

## 部署流程

### 1. 收集硬件与需求（先算账，再动手）

1. 查显存：`nvidia-smi --query-gpu=memory.used,memory.total,compute_cap --format=csv`（5070 Ti 16GB 实际可用约 15.9GB）。
2. 明确需求四要素：**模型规模、是否无审查（Uncensored）、是否多模态（mmproj）、上下文与速度预期**。
3. 显存预算：见 references/hardware-budget.md。原则——权重 + KV 缓存 + 计算缓冲必须 < 可用显存，且留余量。

### 2. 选型（量化档位）

按 references/hardware-budget.md 的档位表选择。16GB 卡、27B 模型的可用档位参考：

| 档位 | 文件大小 | 16GB 适用性 |
| --- | --- | --- |
| Q4_K_M | ~16GB | 撑爆显存，无余量跑长上下文 |
| UD-IQ3_XXS | ~11GB | ✅ 甜点，可 100K 上下文 + 多模态 |
| Q3_K_XL / IQ3_S | 12.4–13.2GB | 32K 以下可用，长上下文危险 |
| IQ2/三值 | <9GB | 显存最省，但智力明显下降 |

无审查版获取：HF 搜 `Qwen3.8-27B-Uncensored-GGUF`（JonathanColetti）、`-Unleashed-GGUF`（SwagMessiah100，Unsloth 动态量化，含 UD-* 档位）等仓库。

### 3. 下载与校验

1. 国内直连 HF 会超时，一律走镜像：URL 模板 `https://hf-mirror.com/<repo>/resolve/main/<file>`；用 `https://hf-mirror.com/api/models/<repo>/tree/main` 拿精确文件清单与大小。
2. 用 `scripts/download_and_verify.ps1` 下载，参数见脚本头部注释。
3. **双校验**：文件字节数一致 + SHA256 一致（HF 页面 Values 里的 sha 或仓库提供的校验值）。校验不过就重下，不要强上。

### 4. 生成启动脚本

1. 用 `scripts/gen_start_bat.ps1` 生成 bat（Windows 下**必须 GBK 编码 + CRLF 行尾**，UTF-8 会导致中文拆碎、命令错乱）。
2. 关键参数（完整表见 references/llama-server-params.md）：
   - 上下文：`-c 102400`（100K 是 16GB 卡甜点；128K 无 MTP 可跑但慢，200K 不可用）
   - KV 量化省显存：`--cache-type-k q4_0 --cache-type-v q4_0`
   - 多模态视觉塔放 CPU 不占显存：`--no-mmproj-offload`
   - 投机采样提速：`--spec-type draft-mtp --spec-draft-n-max 2`（100K 下可提速到 70+ tok/s；128K+ 会反噬，须关闭）
   - 关闭思考（快速版）：`--no-reasoning-preserve`（Harness 无需改配置，同端口切换）
   - 监听：`--host 127.0.0.1 --port 8085`
3. 生成的脚本应含"已在运行则拒绝启动"的防重复检测（重复双击第二实例必 OOM）。

### 5. 启动与验证

1. 双击 bat，等日志出现 `listening on http://127.0.0.1:<port>` 即成功。
2. 健康检查：`curl http://127.0.0.1:8085/health`。
3. 实测速度（短对话与长上下文各一次），达不到预期按"调优"节处理。
4. 多模态模型用一张测试图验证识别（`curl -F "file=@test.png" http://127.0.0.1:8085/infinity` 或客户端发图）。

### 6. 接入 Agent 框架

读 references/harness-integration.md。要点：Provider 用 OpenAI Chat Completions 协议指向 `http://127.0.0.1:<port>/v1`；**手动添加的模型默认按纯文本处理，必须显式声明 `input: [text, image]`** 才能发图。修改配置前先备份。

## 调优（提速 / 提上下文）

按以下顺序尝试，每步实测对比：

1. **投机采样 MTP**：`--spec-type draft-mtp --spec-draft-n-max 2`。上下文 ≤100K 时提速明显（草稿采纳率 50%+）；≥128K 时反噬（草稿缓存挤占显存），关闭。
2. **KV 量化**：`--cache-type-k/v q4_0`，上下文翻倍或 KV 内存减半。
3. **视觉塔不占显存**：`--no-mmproj-offload`（多模态模型）。
4. **关闭思考**：`--no-reasoning-preserve`，输出更快且思考 token 不进历史（省上下文）。
5. **降低上下文**：`-c` 128K→100K 是 16GB 卡的分水岭（52→70 tok/s）。
6. **不要做的**：不要用 CPU/内存分担模型权重（慢约 28 倍）；不要超显存硬上（卡顿+极慢）。

## 反模式

- 不要用 Ollama 加载分离的 mmproj 视觉文件（Modelfile 不支持，报 500）——用原生 llama.cpp。
- 不要重复启动第二个 llama-server 实例（必 OOM：`GGML_ASSERT buffer failed` / `cudaMalloc failed: out of memory`）。
- 不要用 UTF-8/不带 CRLF 写 .bat（双击会命令错乱、中文拆碎）。
- 不要 100K+ 上下文还开 MTP（草稿显存反噬，速度骤降）。
- 不要在 16GB 卡上给 27B 模型开 200K 上下文（实测仅 22 tok/s，不可用）。
- 不要跳过文件校验直接跑（模型损坏会出诡异推理错误）。
- 不要为了"无审查"下载来路不明的合并包——优先官方/知名量化仓库（JonathanColetti、SwagMessiah100、mradermacher）并核对 SHA256。
- Harness 里手动模型不能发图 ≠ 模型问题：先查是否声明 `input: [text, image]`。

## 排障

常见报错与处置见 references/troubleshooting.md。先按表定位，不要反复重启同一个失败配置。

## 资源说明

- `scripts/download_and_verify.ps1`：hf-mirror 下载 + 大小/SHA256 双校验。
- `scripts/gen_start_bat.ps1`：生成 llama-server 启动 bat（GBK+CRLF、防重复、思考/无思考可选）。
- `references/hardware-budget.md`：显存算账与量化档位选择。
- `references/llama-server-params.md`：llama-server 关键参数速查。
- `references/harness-integration.md`：DeepSeek Harness 接入与多模态声明。
- `references/troubleshooting.md`：报错对照表。
