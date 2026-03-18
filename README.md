# lingma-app-timeout-patch

这是一个单文件分发的 Lingma 超时补丁仓库，适合直接通过 GitHub Raw 链接执行。

它会给 Lingma 的 `reasonForCode=80408` 场景加上自动 `resume`。

补丁目标：
- 仅改 `workbench.desktop.main.js` 的单个 `resume` footer 逻辑
- 自动处理 `Response timeout. Click to resume.` 对应的 `80408`
- 自动恢复发出后，直接隐藏原始 `Continue` 按钮和超时提示
- 自动备份，支持回滚
- Lingma 升级后再次执行时，自动轮转旧备份并重建当前版本的活跃备份
- 默认拒绝在 Lingma 运行时改包

## 前提

- `bash`
- `node`
- Windows 需要用 Git Bash 运行

## 一键安装

先关闭 Lingma。

把下面的 `<GITHUB_USER>` 换成你的 GitHub 用户名或组织名。

脚本 raw 地址示例：

```text
https://raw.githubusercontent.com/<GITHUB_USER>/lingma-app-timeout-patch/main/lingma-patch.sh
```

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_USER>/lingma-app-timeout-patch/main/lingma-patch.sh | bash
```

### Windows + Git Bash

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_USER>/lingma-app-timeout-patch/main/lingma-patch.sh | bash
```

如果你的 Lingma 不在默认安装位置，手动指定 bundle：

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_USER>/lingma-app-timeout-patch/main/lingma-patch.sh | bash -s -- --file "/custom/path/to/workbench.desktop.main.js"
```

## 常用命令

查看状态：

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_USER>/lingma-app-timeout-patch/main/lingma-patch.sh | bash -s -- status
```

回滚补丁：

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_USER>/lingma-app-timeout-patch/main/lingma-patch.sh | bash -s -- restore
```

查看当前状态字段：

- `clean`: 当前 bundle 未打补丁，且活跃备份与当前 bundle 没有代际冲突
- `patched-current`: 当前 bundle 已按当前活跃备份/元数据正确打补丁
- `patched-stale`: 当前 bundle 仍带旧 patch，但活跃备份或元数据已经不匹配
- `drifted`: 当前 bundle 没有 patch marker，但现存活跃备份/元数据属于旧代 bundle

Lingma 正在运行但你明确要继续时：

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_USER>/lingma-app-timeout-patch/main/lingma-patch.sh | bash -s -- --force
```

## 给同事分发

最简单的做法是把仓库公开到 GitHub，然后把脚本 raw 地址发给同事。默认不传命令就是 `install`：

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_USER>/lingma-app-timeout-patch/main/lingma-patch.sh | bash
```

脚本会按平台自动推断 Lingma 默认安装路径；如果推断不到，再让同事补 `--file`。

## 安全边界

- 脚本只会修改 `workbench.desktop.main.js`
- 活跃备份始终使用固定文件名：
  - `workbench.desktop.main.js.lingma-auto-resume.backup`
  - `workbench.desktop.main.js.lingma-auto-resume.meta.json`
- 当脚本发现旧代备份需要被替换时，会先归档为：
  - `workbench.desktop.main.js.lingma-auto-resume.backup.<timestamp>`
  - `workbench.desktop.main.js.lingma-auto-resume.meta.json.<timestamp>`
- `restore` 只恢复当前活跃备份，不会自动回退到历史归档
- 如果 Lingma 升级后 bundle 结构变化，脚本会直接报 `Patch target not found`，而不是强行改文件
- 如果 Lingma 升级后当前 bundle 与旧备份不一致，脚本会自动识别 `drifted` / `patched-stale`，归档旧活跃备份，再基于当前 bundle 重新建备份并打补丁
- 当前补丁只适配这一版 bundle 里的 `bEn` / `resume` 逻辑
- 当前模式是“静默恢复”，自动 `resume` 发出后不再向最终用户展示超时 footer
