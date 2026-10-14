# local-llm-deploy — 本地 GGUF 大模型部署与调优技能

> **你的游戏电脑，就是一台免费的 AI 工作站。**
>
> 打游戏的高配显卡（**RTX 5070 Ti 16GB** 实测）：本地跑 **27B 无审查大模型** · **多模态看图** · **100K 上下文** · **70+ tok/s**——不用上云、不用花钱、没有审查。
>
> 把"在 Windows + NVIDIA 显卡上部署 GGUF 大模型（llama.cpp 路线）"踩过的坑、调好的参数、验证过的流程，封装成一个**豆包自定义技能**（也可脱离豆包手动使用）。

- 语言：简体中文
- 适用：本地 AI 部署玩家 / Agent 工作流用户（DeepSeek Harness 等）
- 目标模型：27B 级（Qwen3.8 实测样板）
- 许可证：MIT

---

## 这是什么

一个可重复执行的任务说明书，覆盖本地模型的**全生命周期**：

| 环节 | 内容 | 触发场景 |
| --- | --- | --- |
| 部署新模型 | 选型号 → 镜像下载 → SHA256 校验 → 生成启动脚本 | "帮我装个 XX 模型" |
| 调优加速 | 显存算账、量化档位、MTP/KV 量化/关思考 | "模型太慢了""显存爆了""上下文不够" |
| 接入使用 | Agent 框架（Harness）Provider 配置、多模态声明 | "接入 Harness""本地模型不能看图" |
| 排障 | 12+ 类常见报错对照表 | 启动报错、OOM、截断、bat 乱码 |

---

## 基准硬件配置（本技能的全部参数由此实测得出）

| 项目 | 配置 |
| --- | --- |
| GPU | **RTX 5070 Ti 16GB**（sm_120a，实测可用约 15.9GB） |
| 内存 | 32GB |
| 系统 | Windows（bat 按 Windows 双击场景设计） |
| 引擎 | llama.cpp（llama-server，实测版本 0.6.0-dev） |
| 实测模型 | Qwen3.8-27B-Unleashed-UD-IQ3_XXS（无审查 + 多模态） |

**为什么 16GB 是这套方案的甜点**：27B 模型 Q4 量化约 16GB，恰好撑爆 16GB 显存、无余量跑上下文；降到 UD-IQ3_XXS（11GB）后，权重 + KV + 计算缓冲才有足够余量。

---

## 部署决策链（每一步为什么这么选）

这套方案不是凭空定的，每一步都是对比/实测后的取舍：

1. **为什么不用 Ollama**：`Modelfile` 不支持用 `ADAPTER` 加载分离的 `mmproj` 视觉文件（报 500）。→ 改用原生 llama.cpp。
2. **为什么不用 ninfer/KVMem 极速方案**：官方包全是有审查的；社区无审查版只有三值低智档位。→ 放弃，回到 GGUF。
3. **为什么选 UD-IQ3_XXS 而不是 Q4_K_M / IQ4_XS**：Q4_K_M 16GB 撑爆显存；IQ4_XS 上下文只剩 4–8K；UD-IQ3_XXS 11GB、显存有余量、Unsloth 动态量化 PPL 损失可控（6.48）。
4. **为什么上下文定 100K**：实测 100K+MTP = 70+ tok/s；128K 掉到 44–52；200K 只剩 22 tok/s 不可用。100K 是 16GB 卡甜点。
5. **为什么 KV 缓存量化 q4_0**：上下文内存减半、质量损失小。
6. **为什么视觉塔放 CPU（`--no-mmproj-offload`）**：省约 1GB 显存，多模态模型也能跑长上下文。
7. **为什么开 MTP 投机采样**：≤100K 提速明显（草稿采纳率 50%+）；≥128K 草稿上下文反噬显存、速度骤降，必须关。
8. **为什么 bat 必须 GBK + CRLF**：UTF-8/LF 的 bat 双击会中文拆碎、`echo`/`exit`/`pause` 命令错乱（实测踩坑）。
9. **为什么脚本带防重复启动检测**：显存已满时启动第二个实例必 OOM（`GGML_ASSERT buffer failed`）。
10. **为什么 Harness 要声明 `input: [text, image]`**：手动添加的模型默认按纯文本处理，不声明就不能发图（官方文档要点）。

## 实测性能锚点（5070 Ti 16GB + 27B UD-IQ3_XXS + 多模态）

| 配置 | 短对话 | 21.6K 长请求 |
| --- | --- | --- |
| 100K + MTP | **70–79 tok/s** | 61.5 tok/s（草稿采纳 54%） |
| 128K 无 MTP | 52.9 tok/s | 44.3 tok/s |
| 128K + MTP | 25.2 tok/s | —（草稿反噬） |
| 200K 无 MTP | 22 tok/s | 不可用 |

---

## 硬件适配（显卡不同怎么用）

| 你的显存 | 建议 |
| --- | --- |
| 16GB（同基准） | 直接照抄本技能的参数 |
| 24GB+ | 可升 Q3_K_XL / Q4_K_M 档位，上下文可到 128K+ |
| 8GB | 降到 7–14B 模型，或用 IQ2/三值档 |
| 不确定 | 用 `references/hardware-budget.md` 的显存算账公式推导 |

> 核心方法：`总占用 ≈ 权重大小 + KV 缓存 + 计算缓冲 + 1GB 余量`，必须小于可用显存。

---

## 目录结构

```
local-llm-deploy/
├── SKILL.md                    # 主流程：意图路由 + 部署六步 + 调优 + 反模式
├── references/
│   ├── hardware-budget.md      # 显存算账、量化档位表、实测锚点
│   ├── llama-server-params.md  # 参数速查、服务管理命令
│   ├── harness-integration.md  # Harness 接入 + 多模态声明
│   └── troubleshooting.md      # 报错对照表（OOM/截断/bat 乱码等）
└── scripts/
    ├── gen_start_bat.ps1       # 生成启动 bat（GBK+CRLF、防重复、思考可选）
    └── download_and_verify.ps1 # hf-mirror 下载 + 大小/SHA256 双校验
```

---

## 安装（豆包用户）

1. 豆包 PC 版 →「技能·连接器·伙伴」→「我的技能」→ 右上角「新建 → 上传技能」
2. 把本仓库的 `local-llm-deploy` **文件夹**拖进去
3. 之后说"部署 XX 模型""模型太慢""显存不够""接入 Harness"等，自动触发

## 手动使用（不依赖豆包）

直接读 `SKILL.md` 按部署六步操作；脚本在 Windows PowerShell 下可直接运行。

---

## 无审查模型获取（技能内引用的可靠来源）

- `JonathanColetti/Qwen3.8-27B-Uncensored-GGUF`（原始无审查 + 标准量化）
- `SwagMessiah100/Qwen3.8-27B-Unleashed-GGUF`（Unsloth 动态量化 UD-*，Apache-2.0）
- `mradermacher/...`（imatrix 全档位）

国内下载一律走 `hf-mirror.com` 镜像（HF 直连超时）。

---

## 许可证

MIT License — 详见 `LICENSE`。
