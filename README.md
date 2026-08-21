# Red Packet Rush

Red Packet Rush 是一个固定四人参加的中文纸牌对战原型：玩家在大厅发现房间，在等待房间配置一副或两副牌，随后进行点数抢先、三牌出牌、暗抢、获牌弃牌和最终结算。Colyseus 服务端是唯一规则权威，Godot 客户端只呈现公开状态并提交意图。

> **运行前请先读**：本交付面向 Windows x86_64 desktop。需要 Node.js 22+、Godot 4.7.1 stable（64 位、单精度）和仓库内锁定的 Colyseus Native SDK `godot-v0.17.11`。项目使用 GDScript，不要求 Mono；不要用 Godot 双精度构建，也不要用未锁定的 SDK `main`。

当前 QA 使用 `Godot 4.7.1.stable.mono.official.a13da4feb` console 可执行文件通过；Mono 只是已验证的引擎发行版，不是项目运行时依赖。

## 从零运行

在仓库根目录打开 PowerShell：

```powershell
cd C:\path\to\RedPacketRush
npm --prefix .\server ci
.\scripts\verify.ps1 -GodotPath "C:\path\to\Godot_v4.7.1-stable_win64_console.exe" -SkipInstall
```

`verify.ps1` 会检查已跟踪文件没有依赖目录、编辑器缓存、日志或秘密文件，然后运行服务端测试、TypeScript 构建、Godot editor parse 和全部 `client/tests/run_*_tests.gd` headless runner。省略 `-SkipInstall` 时，脚本会先执行 `npm ci`；只在已按锁文件安装依赖时使用 `-SkipInstall`。失败会立即停止并返回非零退出码。

启动服务端：

```powershell
Push-Location .\server
npm start
Pop-Location
```

默认地址是 `http://127.0.0.1:2567`，WebSocket 地址是 `ws://127.0.0.1:2567`。需要换端口时，在启动前设置 `$env:PORT`；客户端大厅的服务器地址输入框也要改成同一端口。

另开一个终端启动客户端：

```powershell
$godot = "C:\path\to\Godot_v4.7.1-stable_win64_console.exe"
& $godot --path .\client
```

也可以把 Godot 路径放在 `GODOT_PATH`（`GODOT4` 仍兼容）后只传开关：

```powershell
$env:GODOT_PATH = "C:\path\to\Godot_v4.7.1-stable_win64_console.exe"
.\scripts\verify.ps1 -SkipInstall -LiveSmoke
```

## 验证和 smoke

完整检查：

```powershell
.\scripts\verify.ps1 -GodotPath "C:\path\to\Godot_v4.7.1-stable_win64_console.exe"
```

Native SDK 四客户端 smoke：

```powershell
.\scripts\verify.ps1 -GodotPath "C:\path\to\Godot_v4.7.1-stable_win64_console.exe" -LiveSmoke
```

`-LiveSmoke` 调用 `client/tests/run_live_lobby_smoke.ps1`。该辅助脚本会自动分配空闲端口、启动临时 Colyseus 进程、验证大厅匹配/加入、四席准备、一个私有手牌、一个玩家意图和一个公开状态更新，最后清理进程；不需要另开服务端。若直接运行 `.gd` smoke runner，则必须先执行 `npm --prefix .\server start` 并传入 `--endpoint=ws://127.0.0.1:2567`。

可选的干净检出证明：

```powershell
$env:GODOT_PATH = "C:\path\to\Godot_v4.7.1-stable_win64_console.exe"
.\scripts\verify.ps1 -CleanCheckout
```

`-CleanCheckout` 要求当前工作树无改动，然后用 `git clone --no-local` 将当前 `HEAD` 克隆到系统临时目录。它在克隆中执行 `npm ci`、全部测试/构建、四客户端 smoke 和前后两次干净状态检查，完成后删除临时克隆。

## 安装和固定 SDK

服务端依赖只从 `server/package-lock.json` 安装：

```powershell
npm --prefix .\server ci
```

客户端已提交官方 Native SDK `godot-v0.17.11` 的 Windows x86_64 debug/release 二进制。来源、压缩包 SHA-256 和重装命令见 [`client/addons/colyseus/UPSTREAM.md`](client/addons/colyseus/UPSTREAM.md)。重装后应核对哈希 `334ea298f80af77089549c06dda89dfcbd98a33d7177a4a8bee9b8e7dacd9b7c`，再运行验证脚本。

## 玩法和系统边界

服务器保持四个参与者、八张手牌、牌型计分和秘密抢牌的完整状态机。房主在等待房间选择 `one` 或 `two` 副牌，以及 15/30/60 秒行动期限；空席可由机器人填充。牌局开始后，房间从大厅移除。断线的人有 30 秒重连窗口，超时后由机器人接管。

| 阶段 | 客户端可见内容 |
| --- | --- |
| 大厅 | 连接状态、可加入房间和创建入口 |
| 等待房间 | 四个席位、准备状态、房主设置和机器人填充 |
| 牌局 | 点数抢先、当前行动者、牌堆/分数/事件、自己的手牌 |
| 抢牌与弃牌 | 私有选择确认、同步揭晓、获牌后的弃牌 |
| 最终结算 | 两组互不重叠的三牌组合、排名和并列胜者 |

## 原型限制

本项目不包含账号、持久化、密码房、好友/聊天、观战、晚加入、移动/主机/Web 正式导出、可验证生产随机数或生产级反作弊。Playground 和 Monitor 只为本地开发开放；部署时应关闭它们、启用认证与 TLS，并重新评估 Native SDK beta 的平台兼容性。

服务端的详细命令、房间设置和目录边界见 [`server/README.md`](server/README.md)；规则词汇和设计取舍见 [`CONTEXT.md`](CONTEXT.md)、[`docs/adr/0001-use-colyseus-native-sdk-with-gdscript.md`](docs/adr/0001-use-colyseus-native-sdk-with-gdscript.md) 和 [`docs/research/godot-colyseus-integration.md`](docs/research/godot-colyseus-integration.md)。
