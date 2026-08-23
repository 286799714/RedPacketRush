# Red Packet Rush server

这是 Red Packet Rush 原型的权威 Colyseus 服务端。服务端负责大厅房间列表、四人房间准备、牌局规则、随机牌堆、超时决策、机器人和断线接管；Godot 客户端只发送玩家意图。

> **前置条件**：使用 Node.js 22 或更高版本。依赖锁定在 `server/package-lock.json`，请用 `npm ci` 安装。此服务包含开发用 Playground 和 Monitor，不是生产部署配置。

## 快速开始

在本目录执行：

```powershell
npm ci
npm test
npm run build
npm start
```

服务默认监听 `http://127.0.0.1:2567`，WebSocket 客户端端点为 `ws://127.0.0.1:2567`。使用其他端口时设置 `PORT`：

```powershell
$env:PORT = "3000"
npm start
```

启动后，开发 Playground 位于 `http://127.0.0.1:2567/`，Monitor 位于 `http://127.0.0.1:2567/monitor`。两者仅用于本地调试，未配置认证。

## 运行检查

从仓库根目录运行完整检查（包含服务器和 Godot headless 测试）：

```powershell
.\scripts\verify.ps1 -GodotPath "C:\path\to\Godot_v4.7.1-stable_win64_console.exe"
```

只检查已经安装的依赖时可加 `-SkipInstall`。四客户端 Native SDK smoke 会额外启动一个临时本地服务并在完成后清理；启用方式：

```powershell
.\scripts\verify.ps1 -GodotPath "C:\path\to\Godot_v4.7.1-stable_win64_console.exe" -LiveSmoke
```

手工运行 `client/tests/run_live_lobby_smoke.gd` 时，必须先在另一个终端执行 `npm start`，然后传入 `--endpoint=ws://127.0.0.1:2567`。脚本或任一检查失败都会返回非零退出码。

## 可用命令

| 命令 | 用途 |
| --- | --- |
| `npm start` | 以 watch 模式启动 `src/index.ts` |
| `npm test` | 运行规则、房间、并发、断线和机器人测试 |
| `npm run build` | 清理 `build/` 并执行 TypeScript 构建 |
| `npm run schema:generate` | 从 `GameRoomState.ts` 生成 Godot Schema |
| `npm run clean` | 删除可重建的 `build/` 目录 |

## 房间边界

服务注册两个房间：`lobby` 提供实时可加入列表，`game` 是固定四席的等待房间和牌局。创建 `game` 房间时可传入以下设置：

| 设置 | 可用值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `displayName` | 1 至 40 个字符 | `Red Packet Rush` | 大厅显示名 |
| `deckMode` | `one` / `two` | `one` | 一副或两副无大小王牌 |
| `actionDeadlineSeconds` | `15` / `30` / `60` | `30` | 每个可操作阶段的截止时间 |

等待房间必须正好有四个已准备席位才能开始。房主才能修改设置、填充机器人或开始牌局；牌局开始后房间会变为 private/locked 并从大厅消失。

牌局阶段依次包括点数抢先、出牌、出牌公示、暗抢提交、抢牌揭晓、获牌弃牌、弃牌公示、最终结算揭晓和结束。出牌公示、抢牌揭晓、弃牌公示分别持续 3、4、2 秒，均不可提交动作且没有行动截止时间。每名玩家持五张牌，出三张后补三张；获牌玩家临时持六张，可弃其中任意一张（包括刚获得的牌）恢复为五张。牌堆不足三张时，服务器自动从每人的五张手牌中选出得分最高的一组三张并同时公开结算，不等待客户端提交。公开状态只包含牌局审计所需的信息；手牌和未揭晓的抢牌通过针对单个参与者的消息发送。

## 目录导览

- `src/index.ts`：启动 Colyseus 并读取 `PORT`。
- `src/app.config.ts`：注册 `lobby` 和 `game` 房间以及开发路由。
- `src/rooms/GameRoom.ts`：四席房间、权限、超时、机器人和重连边界。
- `src/rooms/LiveLobby.ts`：实时大厅列表。
- `src/match/`：纯规则引擎、牌、随机源和机器人决策。
- `src/rooms/schema/`：同步给 Godot 的公开 Schema。
- `test/`：规则单测、Colyseus 房间集成测试和连续性测试。

## 原型限制

当前版本没有账号、密码房、持久化、好友/聊天、观战、晚加入、排行、生产级随机可验证性或反作弊系统；只保证 Windows x86_64 desktop 的 Godot 4.7.1 单精度运行。机器人是确定性的测试辅助，不代表生产级 AI。部署环境应自行关闭 Playground/Monitor、配置 TLS（`wss://`）和访问控制。
