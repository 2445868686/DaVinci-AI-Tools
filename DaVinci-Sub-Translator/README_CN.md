# DaVinci 字幕翻译器

<div align="center">

# <span style="color: #2ecc71;">DaVinci 字幕翻译器✨</span>

**[English](README.md) | [简体中文](README_CN.md)**
</div>

## 介绍 🚀

DaVinci 字幕翻译器是一个针对 DaVinci Resolve 的插件，能够自动翻译字幕轨道并集成到时间线上，界面支持中英文双语。

## 项目功能 🎉

- 使用流行翻译服务，如 **Google 翻译**、**Microsoft Azure 翻译** 和 **OpenAI**。
- 管理 OpenAI 兼容模型，验证 API 密钥并添加自定义模型。
- 自动导出翻译后的字幕为 `.srt` 并插入到第一个空字幕轨道中。

## 安装 🔧

1. 在 DaVinci Resolve 中打开 **Workspace → Console → Py3**，确保已启用 Python。如果未启用，请按照提示安装。
2. 将 `Sub AI Translator` 文件夹移动到：
   - **Mac**：
     ```bash
     /Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Edit
     ```
   - **Windows**：
     ```powershell
     C:\ProgramData\Blackmagic Design\DaVinci Resolve\Fusion\Scripts\Edit
     ```
3. 运行 `Mac_Install.command`（macOS）或 `Windows_Install.bat`（Windows）以安装依赖。
4. 在 DaVinci Resolve 中通过 **Workspace → Scripts** 启动插件。

更多详细说明请参阅 [Installation-Usage-Guide.html](Installation-Usage-Guide.html)。

## 使用 💡

### 主窗口

- **Translate** – 翻译当前时间线中的所有字幕。
- **Target Language** – 选择目标输出语言。
- **Provider** – 选择 Google、Microsoft 或 OpenAI Format 服务。
- **EN / 简体中文** – 切换界面语言。

### OpenAI Format 设置

- **Model** – 选择或添加模型名称。
- **Base URL** – API 端点地址。
- **API Key** – 访问令牌。
- **Verify** – 验证 API 设置是否有效。
- **Add Model / Delete Model** – 管理自定义模型条目。

### Microsoft 设置

- **Region** 和 **API Key** – Azure 翻译服务凭据。
- **Register** – 打开 Azure 注册页面。

## 注意事项 ⚠️

- 翻译质量取决于所选服务和网络状况。

## 贡献 🤝

欢迎各种形式的贡献！如果遇到问题、建议或 BUG，请通过 GitHub Issues 联系我或提交 Pull Request。

## 支持 ❤️

🚀 **热爱开源与 AI 创新？** 本项目致力于让 AI 工具更**实用**、**易用**。所有软件**完全免费**且**开源**，回馈社区！

如果你觉得本项目对你有帮助，欢迎支持我的工作！你的支持将帮助我持续开发并带来更多有趣功能！💡✨

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/G2G31A6SQU)

## 许可证 📄

© 2025 HB。保留所有权利。
