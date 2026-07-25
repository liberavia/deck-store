# DeckStore

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![CI Build](https://github.com/USERNAME/deck-store/actions/workflows/build.yml/badge.svg)](https://github.com/USERNAME/deck-store/actions/workflows/build.yml)
[![Unit Tests](https://github.com/USERNAME/deck-store/actions/workflows/test.yml/badge.svg)](https://github.com/USERNAME/deck-store/actions/workflows/test.yml)

DeckStore is a modern, open-source App-Store alternative built for SteamOS devices (like the Steam Deck). It is designed to easily find, install, and manage Flatpak packages from Flathub with a controller-first user interface.

## 🚀 Features

- **SteamOS Native Feel:** Built with the Godot Engine for broad hardware support and tailored specifically to a 1280x800 resolution with full controller mapping.
- **Robust Dependency Management:** Install applications alongside their required extensions cleanly and securely.
- **Steam Integration:** Easily add installed Flatpaks as "Non-Steam Games" directly to your Steam library.
- **Multilingual Support:** Enjoy DeckStore in multiple languages (English, German, French, Spanish, Italian, Polish, Ukrainian).

## 🛠️ Manual Installation

If you want to run or test DeckStore locally:

### Using Godot Engine
1. Clone this repository:
   ```bash
   git clone https://github.com/USERNAME/deck-store.git
   cd deck-store
   ```
2. Open the project in the **Godot 4** Editor.
3. Run the project from the editor or export it for Linux/X11.

### Testing on SteamOS
To ensure absolute compatibility outside of the Godot sandbox, read the [Testing on SteamOS Guide](TESTING_ON_STEAM_MACHINE.md) (coming soon, currently being integrated into CI).

## 🤝 Contributing

We welcome contributions! Whether it's fixing bugs, adding languages, or proposing new features. 
Please read our [Contributing Guidelines](CONTRIBUTING.md) to understand our branching model, testing requirements, and versioning rules.

## 📄 License

This project is licensed under the [GNU General Public License v3.0 (GPLv3)](LICENSE).
