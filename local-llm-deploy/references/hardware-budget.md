# 显存算账与量化档位选择

## 显存占用公式

```
总占用 ≈ 权重大小 + KV 缓存 + 计算缓冲 + CUDA/驱动开销
```

- 权重：GGUF 文件大小 ≈ 显存占用（全层 GPU 时）。
- KV 缓存：`2 × 层数 × 隐层维 × 上下文长度 × KV 位宽`。27B 模型 100K 上下文、fp16 KV 约 8–10GB；KV 量化 q4_0 后约减半。
- 计算缓冲：数百 MB 到 1–2GB（含 MTP 草稿上下文）。
- 多模态视觉塔（mmproj）约 0.8–1GB；用 `--no-mmproj-offload` 可放 CPU 侧，不占显存。

**经验法则**：文件大小 ≤ 可用显存 − KV − 缓冲 − 1GB 余量，才稳。

## 16GB 卡（5070 Ti，可用 ~15.9GB）× 27B 模型档位表

| 档位 | 文件大小 | 16GB 适用性 | 备注 |
| --- | --- | --- | --- |
| Q4_K_M | ~16GB | ❌ 撑爆 | 无余量，长请求报 CONTEXT_WINDOW_EXCEEDED |
| UD-IQ3_XXS | ~11.0GB | ✅ 甜点 | 可 100K + KV q4_0 + 多模态；PPL 6.48 |
| Q3_K_S / IQ3_S | ~12.4–12.7GB | ⚠️ 32K 以下 | 长上下文需降 KV |
| Q3_K_M | ~13.6GB | ⚠️ 危险 | 32K + KV q4 勉强 |
| UD-Q3_K_XL | ~13.2GB | ⚠️ 32K 边缘 | PPL 6.40 略好于 XXS |
| Q3_K_L | ~14.7GB | ❌ | 只剩 ~1GB 余量 |
| IQ2_XXS / 三值(1.58bit) | ~6–9GB | ✅ 极省 | 智力明显下降，仅够跑 |

## 量化命名速记

- **Q#_K_X**：llama.cpp 标准 K 量化（S/M/L = 大中小）。Q3_K_M 即 Q3_K。
- **IQ#_X**：imatrix 量化，同档位下略优于 K 系（如 i1-IQ3_S 常优于 Q3_K_S）。
- **UD-**：Unsloth 动态逐张量量化（如 UD-IQ3_XXS、UD-Q3_K_XL），质量分布更智能，PPL 更低。
- **GSQ-RCO**：另一种按张量分配精度的方案，命名独立体系，不能直接按 Q 档对比。

## 实测锚点（5070 Ti 16GB + 27B UD-IQ3_XXS + mmproj）

| 配置 | 短对话 | 21.6K 长请求 |
| --- | --- | --- |
| 100K + MTP | 70–79 tok/s | 61.5 tok/s（草稿采纳 54%） |
| 128K 无 MTP | 52.9 tok/s | 44.3 tok/s |
| 128K + MTP | 25.2 tok/s | —（草稿反噬） |
| 200K 无 MTP | 22 tok/s | 不可用 |

**结论**：100K + MTP 是 16GB 卡甜点；128K 是分水岭；200K 放弃。

## 需求四要素提问模板

1. 目标模型多大？（7B / 14B / 27B / 32B …）
2. 是否必须无审查（Uncensored）？
3. 是否要多模态（看图）？
4. 上下文与速度预期？（如"100K 可接受，50+ tok/s"）

## 获取无审查模型的可靠仓库

- `JonathanColetti/Qwen3.8-27B-Uncensored-GGUF`（原始无审查 + 标准量化）
- `SwagMessiah100/Qwen3.8-27B-Unleashed-GGUF`（Unsloth 动态量化 UD-*，Apache-2.0）
- `mradermacher/...`（imatrix 全档位，i1-* 前缀）

> 仓库模型卡里 PPL 只作相对参考（同套测试内可比），MMLU 120 题小样本有 ±4pt 抽样误差，不要当绝对智力分。
