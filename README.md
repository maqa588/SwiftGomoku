# Swift Gomoku

A native macOS Gomoku board for [Piskvork/Gomocup](https://plastovicka.github.io/protocl2en.htm) engines such as [Rapfi](https://github.com/dhbloo/rapfi).

中文 · [日本語](#日本語) · [English](#english)

## 中文

Swift Gomoku 是一款 macOS 14+ SwiftUI 五子棋软件，支持人机对弈、本地双人、15/19/20 路棋盘、三种规则、悔棋、认输和协议日志。落子音效由 DSP 实时合成，会根据棋子、棋盘位置和木材变化。界面支持简体中文、日语和英语。

应用内置了 ARM64/NEON 版 Rapfi，在 Apple Silicon Mac 上可以直接开始。Intel Mac 需要在“引擎”区域导入自行编译的 x86_64 Rapfi。也可以随时导入其他兼容 Piskvork 的引擎。搜索线程默认使用除一个逻辑核心外的所有 CPU 核心，可在界面中调整。应用通过 `START`、`BEGIN`、`TURN`、`BOARD`、`INFO` 和 `END` 命令通信。

> 连珠模式会发送 `INFO rule 4`。当前版本尚不在界面侧拦截人类玩家的三三、四四禁手。

## 日本語

Swift Gomoku は macOS 14 以降に対応する SwiftUI 製の五目並べアプリです。対エンジン戦、2人対戦、15/19/20 路盤、3種類のルール、待った、投了、プロトコルログに対応します。着手音は石・位置・盤材に応じて DSP でリアルタイム合成されます。簡体字中国語・日本語・英語で利用できます。

Apple Silicon Mac では内蔵の ARM64/NEON 版 Rapfi をそのまま利用できます。Intel Mac では x86_64 版 Rapfi を読み込んでください。他の Piskvork 対応エンジンも読み込めます。探索スレッド数はアプリ内で調整できます。

## English

Swift Gomoku is a SwiftUI app for macOS 14 or later. It supports human-vs-engine and local games, 15/19/20 boards, three rule sets, undo, resign, and a protocol log. Placement sounds are synthesized in real time with DSP and vary by stone, board position, and wood. The interface is localized in Simplified Chinese, Japanese, and English.

Apple Silicon Macs use the bundled ARM64/NEON Rapfi engine by default. Intel Mac users must import an x86_64 Rapfi build. Other Piskvork-compatible engines can also be imported. Search threads default to all but one logical CPU core and are configurable in the Engine section.

## Build

Open `SwiftGomoku.xcodeproj` in Xcode and run the `SwiftGomoku` scheme. The repository intentionally excludes signing identities, per-user Xcode state, unrelated local engine/model files, and secret configuration files.

## License and acknowledgements

Swift Gomoku is free software licensed under **GNU GPL version 3 only** (`GPL-3.0-only`). See [LICENSE](LICENSE).

The bundled [Rapfi](https://github.com/dhbloo/rapfi) ARM64 binary is also GPLv3. Its exact corresponding source commit, build identity, and checksum are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The Piskvork/Renju protocol and interaction design were informed by [wind23/piskvork_renju](https://github.com/wind23/piskvork_renju).
