# Command bar developer tools

参考 uTools 的用法：内容先到，工具跟着内容走。

## 使用

- **自动识别**：命令栏会识别三处内容——输入框里输入或粘贴的文本、打开命令栏时的选中文本、上次打开以来新复制的剪贴板文本（只在空白首页显示「刚复制」一节，开始打字就隐藏）。识别到的工具行副标题直接显示结果，右侧详情栏显示完整结果。
  - Return：复制结果并关闭命令栏
  - Tab：带着这段内容进入工具页
- **工具页**：搜 `json`、`base64`、`url`、`unicode`、`时间戳`、`jwt`、`hash` 直接进入。如果选中文本或剪贴板里有这个工具能识别的内容，会自动带入。结果随输入实时更新。
  - ⌥1…9 切换操作，左上角可以换工具
  - ⌘↩ 复制并关闭
  - ⌘D 分离成独立窗口，用于大段内容或需要并排时
  - Esc 返回搜索
- **开关**：设置 → 命令栏 → 开发工具。关闭后工具入口、自动识别和剪贴板读取全部停止。

## 工具

- JSON：格式化、压缩。保留键顺序、数字原文和字符串转义，不排序、不对长整数四舍五入；报错带行列号。
- Base64：解码（兼容 URL 安全字母表和省略的 `=`）、编码、URL 安全编码。只处理 UTF-8 文本。
- URL：组件解码（`+` 保持不变）、组件编码、解析参数（逐行列出 query，按表单规则把 `+` 还原成空格）。
- Unicode：还原 `\uXXXX`、`\u{…}` 和 JSON 转义，带不带引号都可以；转义时只转非 ASCII 字符，emoji 用 UTF-16 代理对。
- 时间戳：秒、毫秒和日期双向转换；输入为空时显示当前时间。
- JWT：解析 header、payload 和 iat/nbf/exp，不校验签名。
- 哈希：SHA-256、MD5、SHA-1、SHA-512，输入按 UTF-8 精确计算（含空白）。

单次输入上限 256 KiB；超过 32 KiB 的输入在停止输入后再计算。

## 识别规则

只做把握大的猜测，宁可漏掉也不误报：

- JWT：三段、前两段以 `eyJ` 开头。
- JSON：以 `{` 或 `[` 开头，并且能解析。
- 时间戳：10 位或 13 位纯数字，落在 2001 到 2100 年之间；或者常见格式的日期。
- Unicode：包含 `\uXXXX`。
- URL：带 query 的 http(s) 地址，或者包含 `%XX`。
- Base64：至少 8 个字符，不含空格，不是纯十六进制；要含数字、`+/=`，或大小写混排；解码结果必须是可打印的 UTF-8 文本。`test`、`terminal` 这类普通搜索词不会被识别成 Base64。

## 添加工具

在 `CommandBarDeveloperTools.all` 里注册一个 `CommandBarDeveloperTool`：

- 稳定 ID、中英文名称、短名、SF Symbol、搜索关键词
- 操作列表（第一个是默认操作）

要参与自动识别，在 `matches(for:)` 里加一条识别规则。ID 会写进置顶、别名等偏好设置，已发布的 ID 不要改。

## 主要文件

- `Services/CommandBar/CommandBarDeveloperTools.swift`：工具注册、转换、识别、工具页模型
- `UI/CommandBar/CommandBarDeveloperToolsView.swift`：工具页、分离窗口、设置开关
- `CommandBarService.swift`：`.developerTool` 模式、三处识别来源、Tab 和按键处理
- `CommandBarCatalog.swift`：工具入口行和识别行
- `CommandBarDetailPane.swift`：识别行的完整结果预览

验证：`./build.sh --test-suite=developer-tools`、`./build.sh --test-suite=command-bar`、`./build.sh --dev`。
