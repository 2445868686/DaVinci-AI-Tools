<div align="center">
    
# <span style="color: #2ecc71;">DaVinci-Resolve-Whisper </span>

**[English](README.md) | [简体中文](README_CN.md)**

[![GitHub stars](https://img.shields.io/github/stars/2445868686/DaVinci-Resolve-Whisper.svg?style=social)](https://github.com/HEIBA-LAM/DaVinci-Resolve-Whisper/stargazers)

</div>



A powerful script for DaVinci Resolve that integrates the Whisper speech-to-text model to automatically generate subtitles for your timeline. It supports both local high-performance transcription via `faster-whisper` and cloud-based transcription through the OpenAI API, with an optional AI-powered correction feature for superior accuracy.



## Project Features

- **Dual Transcription Modes**: Choose between local processing with `faster-whisper` (no internet required) or the highly accurate OpenAI API.
- **Multiple Models**: Supports all `faster-whisper` models (`tiny`, `small`, `base`, `medium`, `large-v3`) and OpenAI models (`whisper-1`, `gpt-4o-mini-transcribe`, etc.).
- **AI-Powered Correction (Smarter Mode)**: Utilizes a GPT model to intelligently punctuate and refine the transcription, delivering more natural and accurate subtitles.
- **Seamless Integration**: Runs as a simple script within DaVinci Resolve, no complex setup needed.
- **Automatic Workflow**:
    1.  Renders audio from your current timeline or a selected media clip.
    2.  Transcribes the audio using the selected engine.
    3.  Generates a standard `.srt` subtitle file.
    4.  Imports the SRT file directly into the first available subtitle track.
- **Customizable Output**:
    -   Set the transcription language or use auto-detect.
    -   Define the maximum number of characters per subtitle line.
    -   Option to remove time gaps between consecutive subtitles.
    -   Use a "Prompt" or "Hotwords" list to improve recognition of specific names, jargon, or technical terms.
- **Bilingual UI**: Switch between English and Chinese interfaces with a single click.
- **Cross-Platform**: Fully compatible with both Windows and macOS.

## Installation

1.  **Download the Project**:
    Clone the repository to your local machine:
    ```bash
    git clone https://github.com/2445868686/DaVinci-Resolve-Whisper.git
    ```

2.  **Run the Installer**:
    -   **On Windows**: Double-click the `Windows_Install.bat` file.
    -   **On macOS**: Double-click the `Mac_Install.command` file.
    
    The installer will automatically copy the script files to the correct DaVinci Resolve directory.

## Usage

1.  **Open the Script**:
    -   In DaVinci Resolve, go to the **Workspace** menu.
    -   Navigate to **Scripts** -> **Utility**.
    -   Click on **DaVinci Whisper** to launch the script window.

2.  **Configure Settings**:
    -   **Transcription Mode**:
        -   For local processing, uncheck "Use OpenAI API". Select a model from the dropdown. If you haven't downloaded the models, click **Download Model**.
        -   For cloud processing, check **Use OpenAI API**. Select a model and enter your API credentials.
    -   **Smarter (AI Correction)**: Check this box to enable AI-powered punctuation and refinement. This requires an OpenAI API key, even if you are using a local model for the initial transcription.
    -   **Language**: Select the primary language of your audio, or leave it as "Auto" for automatic detection.
    -   **Max Chars**: Set the maximum number of characters you want in a single subtitle line.
    -   **No Gaps**: Check this to make each subtitle start exactly when the previous one ends.
    -   **Phrases / Prompt**: Enter any specific words, names, or phrases (separated by commas) that you want the model to recognize more accurately.


## Support

🚀 **Passionate about open-source and AI innovation?** This project is dedicated to making AI-powered tools more **practical** and **accessible**. All software is **completely free** and **open-source**, created to give back to the community!  

If you find this project helpful, consider supporting my work! Your support helps me continue development and bring even more exciting features to life! 💡✨  

 [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/G2G31A6SQU)  
