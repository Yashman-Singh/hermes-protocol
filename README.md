# Hermes ⚡️🧠

**Hermes** is a fast, local-first voice typing assistant for macOS.
It captures your speech, transcribes it locally using the `FluidAudio` engine (powered by Parakeet TDT models), optionally refines it with a local LLM via [Ollama](https://ollama.com), and injects the text directly into any active application.

## Features 🌟

*   **Local-First Privacy**: No audio ever leaves your device. Everything runs on-device.
*   **Global Hotkey**: Press `Option + S` to start/stop dictating instantly.
*   **LLM Refinement**: Three modes via Ollama:
    *   **Raw** — No modifications, just raw transcription.
    *   **Editor** — Cleans fillers, fixes punctuation and capitalization.
    *   **Writer** — Professional rewrite for clarity and flow.
*   **Smart Injection**:
    *   Directly types into native apps (`Notes`, `TextEdit`) via Accessibility API.
    *   Smart clipboard fallback for web apps and Electron apps (`VS Code`, `Discord`, `Slack`, `Google Docs`).
*   **Model Picker**: Choose from recommended Ollama models (1B–8B) or enter a custom one.
*   **Dynamic Menu Bar**: Shows loading, ready, recording, and refining states at a glance.

## Installation 📦

### Prerequisites
*   macOS 14.0+ (Sonoma) or newer.
*   [Ollama](https://ollama.com) installed and running.
*   An Ollama model pulled (e.g. `ollama pull llama3.2:3b`).

### Recommended Models

| Model | RAM | Speed | Command |
|---|---|---|---|
| `gemma3:1b` | ~1 GB | ⚡ Fastest | `ollama pull gemma3:1b` |
| `llama3.2:3b` | ~2 GB | 🚀 Recommended | `ollama pull llama3.2:3b` |
| `llama3:8b` | ~5 GB | Best quality | `ollama pull llama3:8b` |

### Building from Source
1.  Clone the repository:
    ```bash
    git clone https://github.com/Yashman-Singh/hermes-protocol.git
    cd hermes-protocol
    ```
2.  Open in Xcode:
    ```bash
    xed Hermes/
    ```
3.  Build and Run (`Cmd + R`).

### Distributing to Friends
1.  In Xcode: **Product → Archive**.
2.  In the Organizer: **Distribute App → Copy App**.
3.  Compress the `.app` and share. Recipients need [Ollama](https://ollama.com) running with a model pulled.

## Permissions 🔐

On first launch, the app will request:
1.  **Microphone Access**: To hear your voice.
2.  **Accessibility Access**: To type text into other applications.
3.  **Notifications** (optional): To alert you when Hermes is ready.

## Usage 🎙️

1.  **Launch Hermes**. You'll see a loading icon (⋯) in the menu bar.
2.  Wait for the ready notification — the icon changes to a waveform.
3.  Place your cursor in any text field.
4.  Press **`Option + S`** to start recording.
5.  Speak your mind.
6.  Press **`Option + S`** again to stop.
7.  Watch the text appear!

## Architecture 🏗️

*   **The Ear (Audio)**: `AVAudioEngine` captures 16kHz Float32 audio.
*   **The Brain (ASR)**: `FluidAudio` runs the `Parakeet TDT` model for real-time transcription.
*   **The Refiner (LLM)**: `Ollama` cleans up speech artifacts via `/api/chat`.
*   **The Hand (Injector)**: Accessibility APIs (`AXUIElement`) inject text, with `NSPasteboard` fallback for web/Electron apps.

## License 📄

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgements 🙏

*   **[FluidAudio](https://github.com/FluidInference/FluidAudio)**: The local ASR engine that powers Hermes.
*   **[Parakeet TDT](https://huggingface.co/nvidia/parakeet-tdt-1.1b)**: The underlying speech-to-text model.
*   **[Ollama](https://ollama.com)**: Local LLM inference for text refinement.
