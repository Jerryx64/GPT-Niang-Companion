# GPT-Niang Companion · GPT 娘聊天与侧边陪伴改版

**原作者：[T7moris](https://github.com/T7moris) · 原项目：[T7moris/GPT-Niang](https://github.com/T7moris/GPT-Niang)**

这是由 [Jerryx64](https://github.com/Jerryx64) 维护的非官方改版，基于上游 **v1.3.4 / b92159a**。感谢 T7moris 创作和开源 GPT-Niang，感谢原项目贡献者。本仓库保留上游历史、许可和[完整致谢](README.upstream.md#致谢与许可)。

本版在原额度挂件上增加 **本机聊天入口、任务状态、三个轮动小点、B2 侧边陪伴、平滑过渡和自由拖动**。本次增强适用于 Windows，macOS 目录保留上游实现。

<img src="gpt-niang-usage/assets/gpt-dragon-niang-bust.png" alt="上游原完整形象" width="180"> <img src="gpt-niang-usage/assets/gpt-niang-side-peek-b2.png" alt="改版新增 B2 侧边探头" width="140">

## 1.4.0：降低内存与修复更新

轻量 .NET 守护取代常驻 PowerShell 守护；图片按显示尺寸解码、聊天列表按需创建。受管进程组提交内存硬上限 448 MiB，单进程 384 MiB；挂件超过 320 MiB 停止并等待手动恢复。Codex 独立启动的 MCP 连接不在此预算内。异常启动有次数限制，避免无限重试。右键菜单在点击位置旁边弹出，点击其他应用或网页空白处即关闭。

详细变更见[更新记录](更新记录.md)。

## 我们做了哪些改进

- **聊天与任务状态**：旁边写草稿、打开 Codex 继续；列表可回到原聊天。运行、待授权、待回答、完成、中断和异常分别提示，称呼使用“老大”。
- **默认 3 秒变成小点**：有任务先显示状态文字，无操作后收成三个轮动小点。点击才展开完整聊天，关闭面板保留活动小点和未发送草稿。
- **切应用时陪你工作**：Codex 前台显示原形象；切后台后保留原形象副本，等待后平滑滑移、缩小、淡化为 140 px 侧边探头。
- **位置跟随与自由拖动**：默认按大形象的屏幕、最近侧边和高度出现；趴姿及等待态都能拖动，松手保位。移动大形象后重新对齐。拖动中断动画，释放后从实际位置继续。
- **胸前小点**：后台小点收在角色范围内，随她移动，并适配 DPI，减少对工作区域的遮挡。
- **独立设置**：任务联动、无操作收起、焦点收起、提示气泡、小点及形态动画、左右侧与各项等待时间均可配置。

完整改动和验证范围见 [FORK-CHANGES.md](FORK-CHANGES.md)。额度读取、语录、原完整形象、声音和原有缩放功能来自上游。

## Windows 安装

需要 Windows 10/11、**Node.js 24 LTS 或更新版本**，以及已登录的 Codex 桌面端。

建议用 Git 克隆本改版的 `companion` 分支到长期保留的目录，再双击根目录 `安装GPT娘.cmd`。安装器会注册本地插件及用户级启动任务，不需要管理员权限。首次启动或加载插件后，可能需要重新打开 Codex。

```powershell
git clone --branch companion https://github.com/Jerryx64/GPT-Niang-Companion.git
cd GPT-Niang-Companion
.\安装GPT娘.cmd
```

若已安装原版，请先按[上游移动与停用说明](README.upstream.md#更新移动与卸载)备份、停用旧安装，再迁移到新目录；安装器会检查旧路径归属，避免两份挂件同时争用个人数据。这个仓库沿用上游插件标识和个人数据位置。

**更新方式：**下载[本仓库最新 Windows Release](https://github.com/Jerryx64/GPT-Niang-Companion/releases/latest)，完整解压并运行 `安装GPT娘.cmd`。v1.4.0 起内置更新只跟随本改版，API 限流时自动使用 Release 更新清单。旧版首次升级需手动覆盖程序文件并重新安装，个人设置保留。Git 克隆安装仍使用 `git pull`，不会被整包更新覆盖。

## 使用与设置

| 操作 | 效果 |
| --- | --- |
| 点原完整形象 | 沿用上游额度/语录交互 |
| 点击状态、小点或侧边探头 | 打开聊天输入和本机聊天列表 |
| 输入 Enter / Shift+Enter | 打开 Codex 继续 / 换行；不会在挂件中自动发送 |
| 拖动趴姿或等待态 | 自由移动并保存位置，拖动不会误触发聊天 |
| 右键角色 | 打开设置；点击外部关闭整组菜单 |
| 聊天显示与收起 | 开关无操作/焦点收起、轮动、提醒并分别设置延时 |
| 显示与位置 | 侧边模式、左右侧、形态动画和切应用后的等待时间 |

默认状态提示停留 3 秒、切形态等待 3 秒、任务结束后 2 秒隐藏，延时可调为 0–60 秒。形态动画尊重系统减少动画设置。原有自定义语录、位置、大小和声音设置继续保留。

## 待授权提示与钩子

插件包含 PermissionRequest、PostToolUse、Stop、Interrupt 四个信息钩子。**每位使用者都应先审阅 `gpt-niang-usage/hooks/hooks.json` 和 `runtime/chat-hooks.mjs`，再通过 Codex 官方 `/hooks` 流程信任。**启用插件不等于信任钩子；修改定义后可能需要重新审核。参见[官方钩子说明](https://learn.chatgpt.com/docs/hooks)。

钩子返回空 JSON，只记录会话、时间和关联指纹，用于“老大，等你授权”等状态，不作批准或拒绝决定，不保存命令正文。钩子未加载时，普通运行和日志提问状态仍能读取；待授权提示需实际回调生效。

## 本地数据

新增聊天功能只读本机 Codex 聊天索引和日志，提取标题、路径、时间及状态，快照写到 `%LOCALAPPDATA%\GPTNiangUsage\state`；没有新增云端上传或遥测。不接入远程电脑或 ChatGPT 网页聊天，快照过期会显示待确认。

本仓库不含开发机安装配置、账户快照、聊天记录、钩子信任记录或个人设置。原版数据与安装说明见 [README.upstream.md](README.upstream.md)。

## 验证

```powershell
cd gpt-niang-usage
npm test
npm run test:windows
```

Windows 检查包含聊天生命周期、草稿、钩子入口、真实 WPF 过渡与拖动、位置重载、负坐标显示器及 96/120/144/192 DPI 布局。macOS 保留上游源代码和测试，本次 Windows 增强尚未移植到 macOS。

## 原作者、贡献与许可

- **原作与维护：[T7moris](https://github.com/T7moris)**；原仓库为 [T7moris/GPT-Niang](https://github.com/T7moris/GPT-Niang)。原作者和各位贡献者的致谢保留在 [README.upstream.md](README.upstream.md#致谢与许可)。
- **本改版维护：[Jerryx64](https://github.com/Jerryx64)**；新增内容详见 [FORK-CHANGES.md](FORK-CHANGES.md)。
- 代码和一般文档沿用 [MIT License](LICENSE)，保留原有版权声明。
- 角色图片及派生图**不属于代码 MIT 授权范围**，适用[原角色素材声明](gpt-niang-usage/assets/CHARACTER-NOTICE.txt)和 [B2 素材说明](gpt-niang-usage/assets/B2-NOTICE.md)，仅用于本项目及非商业副本的挂件/项目展示；商业用途需另行取得授权。
- 原语录许可见 [quotes-LICENSE.txt](gpt-niang-usage/assets/quotes-LICENSE.txt)。本项目不是 OpenAI、DeepSeek 或原作者的官方发布版本。