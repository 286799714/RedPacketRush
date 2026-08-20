# Godot 4.x 与 Colyseus 0.17 集成研究

研究日期：2026-08-20  
范围：本仓库的 `client/` Godot 项目与 `server/` Colyseus 项目，目标是为原型选择可维护的大厅、房间和局内通信边界。

## 结论

Colyseus 组织已经提供官方维护的 Godot 客户端：基于 GDExtension 的 **Colyseus Native SDK Godot 版**。本原型应固定使用 GitHub Release `godot-v0.17.11` 的 `colyseus-godot-0.17.11.zip`，把其中的 `addons/colyseus` 放进 `client/`，而不是用 Godot 内置 `WebSocketPeer` 重新实现 Colyseus 协议。

这不是“已由官方声明精确支持本仓库每个 patch 版本”的证明：官方 Godot SDK 的示例锁文件使用 `colyseus` 0.17.8，本仓库解析到 0.17.10；但二者处于同一 0.17 协议线，Schema 也都在 4.0 线，且协议常量和消息/状态处理路径一致。因此，**直接兼容是合理且低风险的原型假设，仍应在交付前做一次四客户端 smoke test**。不需要额外的自定义 transport/API gateway；只有在不能接受官方 GDExtension beta 或目标平台没有对应原生二进制时，才值得退回自定义边界。

## 版本核对

| 项目 | 证据中的版本 | 结论 |
| --- | --- | --- |
| Server 声明 | `colyseus: ^0.17.6`、`@colyseus/schema: ^4.0.0` | [server/package.json](../../server/package.json) |
| Server 实际安装 | `colyseus 0.17.10`、`@colyseus/core 0.17.50`、`@colyseus/schema 4.0.31`、`@colyseus/ws-transport 0.17.13`、`@colyseus/shared-types 0.17.6` | [server/package-lock.json](../../server/package-lock.json) |
| 官方 Godot SDK | `godot-v0.17.11`，发布包名 `colyseus-godot-0.17.11.zip` | [官方 Release](https://github.com/colyseus/native-sdk/releases/tag/godot-v0.17.11) |
| 官方 SDK 示例服务器 | `colyseus 0.17.8`、`@colyseus/core 0.17.36`、`@colyseus/schema 4.0.12`、`@colyseus/ws-transport 0.17.9`、`@colyseus/shared-types 0.17.6` | [SDK tag 的 example-server/package-lock.json](https://github.com/colyseus/native-sdk/blob/godot-v0.17.11/example-server/package-lock.json) |
| Godot 项目 | Godot feature `4.7`、Mobile；仓库内没有 C# 脚本 | [client/project.godot](../../client/project.godot) |

官方 Godot SDK 的 GDExtension 文件声明 `compatibility_minimum = "4.1"`，其随 tag 的 `extension_api.json` 是 Godot 4.5.1。Godot 官方文档说明，面向较早 Godot 小版本的 GDExtension 应能运行在较新的小版本（反向不成立）；所以 4.5.1 构建的扩展在 4.7 上具备合理的前向兼容依据。项目必须使用 **单精度**引擎构建；Godot 文档说明双精度引擎需要匹配双精度扩展。

来源：[Godot GDExtension 版本兼容性](https://github.com/godotengine/godot-docs/blob/3eb52d4a9a4bf631ce27739fc84243cb0263be4f/tutorials/scripting/cpp/about_godot_cpp.rst#version-compatibility)、[Godot `.gdextension` 文件规范](https://github.com/godotengine/godot-docs/blob/9b87e0148a0e2dbdf54ac65977357172526e5c7a/engine_details/engine_api/gdextension/gdextension_file.rst)、[Godot SDK extension_api.json](https://github.com/colyseus/native-sdk/blob/godot-v0.17.11/platforms/godot/include/extension_api.json)。

## 官方客户端的边界

官方文档把该客户端描述为 Godot 4.x 的 GDExtension，支持 Windows、macOS、Linux、iOS、Android 和 Web。它明确标注 GDExtension **beta**，并明确说明不支持 Godot Mono；Mono 项目应改用官方 `Colyseus` NuGet 包（版本约束 `0.17.*`）。本仓库目前是 GDScript 项目，但实际运行时仍应确认使用的是普通 Godot 编辑器/导出模板，而不是 Mono 变体。

官方 GDScript API 已覆盖本原型需要的连接层：

```gdscript
var client = Colyseus.Client.new("ws://localhost:2567")
var room = client.join_or_create("battle")
room.joined.connect(_on_joined)
room.state_changed.connect(_on_state_changed)
room.message_received.connect(_on_message_received)
room.error.connect(_on_error)
room.left.connect(_on_left)
room.send_message("command", {"value": 1})
```

`join_or_create`、`create`、`join` 和 `join_by_id` 先走 Colyseus 的 HTTP matchmaking/seat reservation，再建立房间 WebSocket；客户端不应把“直接连一个 WebSocket URL”当作完整的加入流程。官方 API 文档还说明房间消息使用 MsgPack，房间状态自动同步，并支持状态回调与断线重连。

来源：[官方 Godot 入门页（源文件）](https://github.com/colyseus/docs/blob/4fe5986ccd221f1f958f624ae58f861046a155e1/pages/getting-started/godot.mdx)、[官方 Client SDK API](https://docs.colyseus.io/sdk)、[Native SDK Godot README](https://github.com/colyseus/native-sdk/blob/b0da87edb97e2f6333655b8d051f02e8b05d0973/platforms/godot/README.md)。

## 协议与 Schema 约束

如果绕过官方 SDK，Godot 端至少要实现以下部分，单纯使用 `WebSocketPeer` 的文本/二进制收发是不够的：

1. HTTP matchmaking：`matchmake/joinOrCreate/<roomName>` 等请求、选项 JSON、seat reservation 解析，以及 `sessionId`/`reconnectionToken`。
2. 房间 WebSocket URL 和握手：reservation 后连接 `processId/roomId`，处理 `JOIN_ROOM` 握手和 ACK。
3. Colyseus 二进制帧：协议号 9–17，包括 `JOIN_ROOM=10`、`ROOM_DATA=13`、`ROOM_STATE=14`、`ROOM_STATE_PATCH=15`、`ROOM_DATA_BYTES=17`。
4. MsgPack：字符串/数字消息类型和 payload 的编码/解码。
5. `@colyseus/schema` 4.x 的 reflection handshake、完整状态和 delta patch 解码；断线重连还要保留现有 serializer 状态。

这些不是推测：官方 server 的 `Protocol.ts` 定义了相同的房间协议号和 MsgPack 构帧，官方 Native SDK 的 `protocol.h`、`room.c` 实现了相同的握手、状态、patch 和消息分派。[Colyseus 0.17 server Protocol.ts](https://github.com/colyseus/colyseus/blob/0.17/packages/shared-types/src/Protocol.ts)、[Native SDK protocol.h](https://github.com/colyseus/native-sdk/blob/godot-v0.17.11/include/colyseus/protocol.h)、[Native SDK room.c](https://github.com/colyseus/native-sdk/blob/godot-v0.17.11/src/room.c)。

Schema 方面，官方 Godot 文档推荐运行：

```sh
npx schema-codegen src/rooms/schema/* --gdscript --bundle --output ../colyseus/schema/
```

官方 `godot-v0.17.11` 测试还覆盖了 GDScript 自定义 Schema 的 MAP、ARRAY、REF、STRING、NUMBER、BOOLEAN 和 typed decode，说明状态同步路径不是只有裸消息 demo。[官方 Godot Schema 测试](https://github.com/colyseus/native-sdk/blob/godot-v0.17.11/platforms/godot/tests/test/test_gdscript_schema.gd)。

## 对本原型的建议

### 采用方案

1. **固定 SDK 版本**：下载 `godot-v0.17.11` release zip，提交或以明确的构建步骤缓存 `addons/colyseus`；不要直接跟随 Native SDK `main`，因为官方 README 明确说该项目仍在积极开发、可能有 breaking changes。
2. **使用 GDScript API**：普通 Godot 4.7、单精度、客户端 endpoint 以 `ws://`（本地）或 `wss://`（部署）配置；不要在客户端复制牌局规则，服务器保持权威。
3. **Schema + commands**：将大厅/房间成员、房主配置、阶段、玩家公开信息和可公开的牌局状态放入 Schema；将 `create_room`、`set_config`、`start_game`、`play_cards`、`claim_card`、`discard_card`、`settle` 等动作作为带校验的房间消息。玩家私有手牌/暗标应使用 Schema filter 或按玩家发送的消息，避免把秘密信息放进所有客户端可见的根状态。
4. **先做连接冒烟测试**：在正式牌局逻辑前，用 4 个 Godot 客户端验证 `join_or_create`、`join_by_id`、房主配置广播、`state_changed`、MsgPack command、房间退出和一次断线重连。

### 暂不采用自定义 API boundary

自定义 JSON HTTP/WebSocket gateway 只有在下列情况才有价值：无法分发官方 GDExtension 二进制、必须使用 Godot Mono、或需要完全摆脱 beta 依赖。那条路线应由 Node 侧 gateway 终止 Colyseus，再给 Godot 一个版本化 JSON 协议；否则由 Godot 直接实现上述 matchmaking、二进制协议、MsgPack 和 Schema delta，会把原型变成一次新的客户端 SDK 维护工作，并增加重连、秘密信息过滤和版本升级风险。

## 风险与验收标准

- **Beta 风险**：官方文档要求报告问题；把 SDK 版本 pin 住，并在 Windows 编辑器/导出包上各跑一次连接测试。
- **平台风险**：Web 导出需要启用 Extensions Support；官方 SDK README 还要求 Web 使用 dlink-enabled export templates。Android 导出必须授予 Godot 官方文档要求的 `INTERNET` 权限。
- **TLS 风险**：部署使用 `wss://`；0.17.11 changelog 专门修复了 Android WSS/HTTPS matchmaking 的证书链问题，但仍应以真实证书做测试。[0.17.11 changelog](https://github.com/colyseus/native-sdk/blob/godot-v0.17.11/platforms/godot/CHANGELOG.md#01711)
- **版本风险**：当前证据证明的是同一 0.17 协议线和可行的 patch 兼容性，不是每个未来 patch 的 SLA。若升级 server 到 0.18 或升级 Schema 大版本，应重新锁定并执行客户端/服务器兼容测试。

本研究因此选择：**官方 Godot Native SDK 0.17.11 + Colyseus server 0.17.10（Schema 4.0.x）直接连接，Schema 负责同步、房间消息负责动作，服务器权威；不增加自定义 transport。**
