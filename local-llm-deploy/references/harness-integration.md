# DeepSeek Harness 接入本地模型

## 目标

让 Harness 通过 OpenAI 兼容协议使用本地 llama-server（`http://127.0.0.1:8085/v1`）。

## 配置位置（桌面版）

Harness 桌面版配置入口是 profile 的 patch 文件：

```
$DSH_HOME/profiles/desktop/cordis.patch.yml
```

> Web 版是 `$DSH_HOME/settings.yaml`，结构相同（都是 patch 树）。

## Provider 配置模板

```yaml
- id: llm-pi-ai
  name: "@deepseek-ai/dsh-llm-pi-ai"
  config:
    providers:
      local-llama:                      # Provider ID（小写、稳定）
        displayName: 本地Qwen3.8-27B     # 界面显示名
        apiKeyEnv: LOCAL_LLAMA_API_KEY  # 无密钥时任意环境变量名
        api: openai-completions         # 协议：OpenAI Chat Completions
        baseURL: http://127.0.0.1:8085/v1
        models:
          - id: models\xxx.gguf          # 模型 ID = llama-server 返回的模型名
            name: models\xxx.gguf
            input: [text, image]         # ← 多模态声明（见下）
```

另在 `agent-default-model` 条目（`@deepseek-ai/dsh-agent-default-model`）把默认模型指向该 provider。

## 多模态声明（图片识别关键）

**手动添加的模型，Harness 无法自动知道是否支持图片，默认按纯文本处理** → 发图被拒（提示"当前模型不支持图片"）。

修复：在模型条目显式声明：

```yaml
models:
  - id: models\xxx.gguf
    input: [text, image]
```

- 这是对上游能力的**声明**，不是自动检测；声明错误只会把失败推迟到请求阶段。
- 修改前**备份** patch 文件（复制 .bak）。
- 改完**重启 Harness + 新建会话**验证（旧会话可能缓存"纯文本"判断）。
- 回滚：恢复备份，或移除 `image` 声明。

## 验证清单

1. 服务在跑（`curl http://127.0.0.1:8085/health` 返回 ok）。
2. Harness 设置→模型：Provider 存在、能"获取可用模型"（GET /models 生效）。
3. 新建会话选该模型，发短文本（确认不是缓存）。
4. 发一张不含敏感信息的测试图（确认多模态声明生效）。
5. 记录 Provider ID、模型 ID 与日期，便于回查。

## 常见坑

- Provider ID 大小写/拼写变了 → 请求、会话、默认模型全部失效，改名要新增 ID 再删旧的。
- baseURL 末尾 `/v1` 是 OpenAI 兼容路径，Harness 会在此基础上拼 `/chat/completions`。
- "获取可用模型" 401：查凭据；上游没实现 GET /models 就手动填模型 ID，不要反复换 baseURL。
- 图片被拒分两段：发图前被拒 = 没声明（改 input）；到达后被拒 = 声明与真实能力不符（移除声明）。
