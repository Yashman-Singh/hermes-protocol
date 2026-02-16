# Hermes ⚡️🧠

**Hermes** is a fast, local-first voice typing assistant for macOS. 
It captures your speech, transcribes it locally using the `FluidAudio` engine (powered by Parakeet TDT models), and injects the text directly into any active application.

## Features 🌟

*   **Local-First Privacy**: No audio ever leaves your device. Everything runs on-device using ML.
*   **Global Hotkey**: Press `Option + Space` (or your custom shortcut) to start listening instantly.
*   **Smart Injection**:
    *   Directly types into native apps (`Notes`, `TextEdit`).
    *   Smart clipboard fallback for Electron apps (`VS Code`, `Discord`, `Slack`).
*   **Dynamic Menu Bar**: Shows recording state at a glance.

## Installation 📦

### Prerequisites
*   macOS 14.0+ (Sonoma) or newer.
*   Xcode 15+ (for building from source).

### Building from Source
1.  Clone the repository:
    ```bash
    git clone https://github.com/yourusername/Hermes-Protocol.git
    cd Hermes-Protocol
    ```
2.  Open `Hermes.xcodeproj` in Xcode.
    ```bash
    xed .
    ```
3.  **Disable App Sandbox** (Required for Accessibility Injection):
    *   Go to Project Settings -> Targets -> Hermes -> Signing & Capabilities.
    *   Remove "App Sandbox".
4.  Build and Run (`Cmd + R`).

## Permissions 🔐

On first launch, the app will request:
1.  **Microphone Access**: To hear your voice.
2.  **Accessibility Access**: To type text into other applications.

## Usage 🎙️

1.  **Launch Hermes**. You'll see a waveform icon in the menu bar.
2.  Place your cursor in any text field.
3.  Press **`Option + S`** (Default Hotkey).
4.  Speak your mind.
5.  Press **`Option + S`** again to stop.
6.  Watch the text appear magicially!

## Architecture 🏗️

*   **The Ear (Audio)**: `AVAudioEngine` captures 16kHz Float32 audio.
*   **The Brain (ASR)**: `FluidAudio` (Swift) runs the `Parakeet TDT` model for real-time transcription.
*   **The Hand (Injector)**: Accessibility APIs (`AXUIElement`) inject text, with `NSPasteboard` fallback for resistant apps.

## License 📄

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgements 🙏

*   **[FluidAudio](https://github.com/FluidInference/FluidAudio)**: The incredible local ASR engine that powers Hermes.
*   **[Parakeet TDT](https://huggingface.co/nvidia/parakeet-tdt-1.1b)**: The underlying speech-to-text model.


