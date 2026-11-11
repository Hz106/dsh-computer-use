# dsh-computer-use

给 [DeepSeek Harness](https://github.com/deepseek-ai) 的「电脑操作」插件：让 Agent 能截图、看窗口、移动鼠标、点击、拖拽、打字、按快捷键。

> ⚠️ **它会使用你真实的鼠标和键盘。** 不是虚拟鼠标，调用期间光标会真的移动、窗口会真的被点击。这是本插件有意的设计取舍（见下面「为什么不用虚拟鼠标」）。

## 工具

一个工具 `computer_use`，用 `action` 选择动作：

| action | 作用 | 主要参数 |
| --- | --- | --- |
| `windows` | 列出可见窗口（句柄、标题、进程、位置尺寸） | — |
| `screenshot` | 截全屏，返回 PNG 路径，用 `read_image` 查看 | — |
| `focus` | 把某个窗口切到前台 | `window`（标题或进程名片段） |
| `move` | 移动光标 | `x` `y` |
| `click` | 点击（可右键、双击） | `x` `y` `button` `double` |
| `drag` | 从一点拖到另一点 | `x` `y` `toX` `toY` |
| `type` | 向当前焦点输入文本（走剪贴板，中文没问题） | `text` |
| `key` | 按组合键 | `keys`，如 `ctrl+s`、`enter`、`f5` |

坐标是**物理像素**、以虚拟屏幕左上角为原点（进程已 `SetProcessDPIAware()`，125%/150% 缩放下截图坐标和点击坐标一致）。

## 为什么用真实鼠标

真正"不碰用户光标"的方案只有三条，都有明显代价：

- **窗口消息注入**（`PostMessage` 合成 `WM_LBUTTONDOWN`）：不移动光标，但 Chromium/Electron/Canvas 类应用基本忽略合成消息，覆盖不了大多数现代界面。
- **独立桌面 / 沙箱**：程序放在另一个 WindowStation 里跑，用户看不见、也点不到，且 `SendInput` 只能打进当前活动桌面，仍要靠消息注入。
- **虚拟机**：最接近 Codex 的"虚拟电脑"，但那是另一套基础设施。

所以这一版选择直接驱动真实输入，代价是**调用期间不要抢鼠标**。Agent 在描述里也被要求先让用户别动设备。

## 安装

```powershell
git clone https://github.com/<你>/dsh-computer-use.git
```

然后让 DSH 安装这个本地包（插件 → 从本地目录安装，或让 agent 调）：

```
plugin_manager install_bundle target="<克隆下来的绝对路径>"
```

安装后工具 `computer_use` 会出现在 Agent 的工具列表里，下一个回合即可调用。

## 环境与限制

- 仅 Windows（依赖 `user32.dll` 与 Windows PowerShell 5.1）。
- 每次调用会起一个 PowerShell 进程，首次约 0.5–1 秒；截图坐标是全屏物理像素。
- `type` 走剪贴板：会覆盖你当前的剪贴板内容。
- 没有权限沙箱：插件一旦启用，Agent 就能操作整台桌面。请在不需要时停用它。

## 卸载

```
plugin_manager remove_bundle target="dsh-computer-use"
```

## License

MIT
