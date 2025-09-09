# DaVinci Sub Translator

  <div align="center">
    
# <span style="color: #2ecc71;">DaVinci Sub Translator✨</span>

**[English](README.md) | [简体中文](README_CN.md)**
</div>


## Introduction 🚀

DaVinci Sub Translator is a plugin for DaVinci Resolve that automatically translates subtitle tracks using online services. The interface is bilingual (English/中文) and integrates directly with the timeline.

  

## Project Features  🎉

- Use popular providers such as **Google**, **Microsoft Azure**, and **OpenAI** for subtitle translation.

- Manage OpenAI compatible models, verify API keys and add custom models.

- Automatically export translated subtitles to `.srt` and insert them into the first empty subtitle track.

-

## Installation 🔧

1. In DaVinci Resolve open **Workspace → Console → Py3** to ensure Python is enabled. If not, follow the prompt to install it.

2. Move the `Sub AI Translator` folder to:

 - **Mac**: 
 ```
/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Edit`
```

- **Windows**: 
```
C:\ProgramData\Blackmagic Design\DaVinci Resolve\Fusion\Scripts\Edit
```



3. Run `Mac_Install.command` (macOS) or `Windows_Install.bat` (Windows) to install dependencies.

4. Launch the plugin from **Workspace → Scripts**.

  

Detailed instructions are available in [Installation-Usage-Guide.html](Installation-Usage-Guide.html)

  

## Usage 💡

### Main Window

- **Translate** – translate all subtitles in the current timeline.

- **Target Language**  – choose the output language.

- **Provider**  – select Google, Microsoft, or OpenAI Format.

- **EN / 简体中文** – toggle the interface language.

  

### OpenAI Format Settings

- **Model** – choose or add a model name.

- **Base URL** – API endpoint.

- **API Key** – access token.

- **Verify** – check that the API settings work.

- **Add Model / Delete Model** – manage custom entries.

  

### Microsoft Settings

- **Region** and **API Key** – Azure Translator credentials.

- **Register** – open the Azure registration page.

## Notes ⚠️

- Translation quality depends on the chosen service and network conditions.

  

## Contribution 🤝

Contributions of any kind are welcome! If you have any issues, suggestions, or bugs, please contact me via GitHub issues or submit a pull request.

  

## Support ❤️

🚀 **Passionate about open-source and AI innovation?** This project is dedicated to making AI-powered tools more **practical** and **accessible**. All software is **completely free** and **open-source**, created to give back to the community!

  

If you find this project helpful, consider supporting my work! Your support helps me continue development and bring even more exciting features to life! 💡✨

  

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/G2G31A6SQU)

## License 📄

© 2025 HB. All Rights Reserved.