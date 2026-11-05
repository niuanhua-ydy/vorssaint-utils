# Command Bar 翻译

## 使用

1. 激活命令栏，选择「翻译」（可搜索 `翻译`、`translate`、`fanyi`）。
2. 输入或粘贴文本，选择原文语言、目标语言和服务。
3. Return 翻译，Shift-Return 换行；支持停止、重试和复制完整译文。
4. Esc 返回原来的搜索，清除本次原文和译文；关闭命令栏取消正在进行的请求。

翻译是命令栏的按需子工具，跟随命令栏模块的可用性，不新增后台服务。
一次最多 10,000 字符，超长文本会提示分段，不会静默截断原文。

## 服务

- **Apple 系统翻译**：macOS 15+，不需要 API Key，使用本机模型。首次翻译由系统提示下载语言包；短文本无法确定语言时，由系统提供语言选择对话框，也可事先在命令栏指定原文语言。
- **AI**：在「设置 → 命令栏 → 翻译 → AI」配置接口格式、服务地址、模型和 API Key，然后保存。复用现有客户端，支持 Chat Completions 兼容接口、Responses 和 Anthropic Messages。只保存一组当前配置，不做服务列表和同时对照。
- 服务地址可填域名、`/v1` 地址或完整接口地址；非本机地址必须使用 HTTPS，不接受 URL 中的账号、密码、查询参数或 fragment。
- 本机 HTTP 服务也使用现有客户端的 API Key 字段；无鉴权的兼容服务需填写其接受的占位 Key。
- AI 设置与 ClipNote 独立，不自动读取或复用 ClipNote 的账号，不自动回退到其他服务。

API Key 按应用 bundle ID 隔离保存在 Keychain，更新失败保留原有密钥。
普通配置参与设置备份，密钥、原文和译文不参与。
仅主动提交才发送文本；翻译文本不进入命令栏的搜索学习记录。

## 交互参考与范围

参考 [Bob 输入翻译](https://bobtranslate.com/guide/quickstart/translate.html) 的原文/译文、语言选择和按键提交，以及 [Bob 服务配置](https://bobtranslate.com/guide/advance/service.html) 的内置与自配服务划分。
没有照搬独立浮窗、多服务并排、OCR、词典、划词、历史收藏或插件体系。

## 主要文件

- `Sources/Vorssaint/Services/CommandBar/CommandBarTranslation.swift`：输入验证、请求生命周期、AI 流式调用与 Keychain。
- `Sources/Vorssaint/UI/CommandBar/CommandBarTranslationView.swift`：翻译页面及 Apple Translation 会话。
- `Sources/Vorssaint/UI/Settings/CommandBarTranslationSettings.swift`：AI 配置表单。
- `Sources/Vorssaint/Core/CommandBarTranslationStrings.swift`：15 种界面语言。
- `CommandBarCatalog.swift`、`CommandBarService.swift`、`CommandBarView.swift`：入口、模式切换、键盘与关闭行为。
- `Defaults.swift`、`CommandBarSettings.swift`、`CommandBarStrings.swift`、`README.md`、`PRIVACY.md`：配置和说明。
- `Tests/CommandBarTranslationTests.swift`：请求隔离、取消、流式完成、失败、截断、备份与本地化测试。
- `Tests/MetricsTests.swift`、`Tests/UninstallerFlowTests.swift`、`build.sh`：测试注册与共享模式夹具。

## 本次验证

```sh
./build.sh --dev
./build/VorssaintDeveloper --selftest
./build.sh --test-suite=translation --test-suite=command-bar --test-suite=clipnote \
  --test-suite=localization --test-suite=uninstaller --test-suite=cleaner
git diff --check
```

- 开发构建与自检成功；6 组定向测试共 11,049 项检查通过，其中翻译 63 项。
- macOS 27.2 隔离 QA 副本实测：命令栏翻译入口、Return 进入页面、自动聚焦、输入提交、系统语言选择/语言包下载弹窗、结果显示。下载英语和简体中文语言包后，`Hello, world!` 得到 `你好，世界！`。
- 实机发现并修正：`LanguageAvailability.status(for:)` 对短文本提前抛错会阻断系统语言选择；自动检测现在直接交给可呈现 UI 的 TranslationSession。
- 未使用真实 AI 服务密钥进行在线验收；AI 流式、取消和错误行为为测试流验证，协议编解码由复用客户端的回归测试覆盖。
- 未在 macOS 14/15 设备或 Dynamic Island 内嵌模式实测。开发构建使用 macOS 14 部署目标，Apple API 由 macOS 15 可用性检查保护。
- 没有替换已安装应用，也没有 commit/push。临时 QA 使用独立 bundle ID，测试后停止。
