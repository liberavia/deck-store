# DeckStore

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![CI Build](https://github.com/liberavia/deck-store/actions/workflows/build.yml/badge.svg)](https://github.com/liberavia/deck-store/actions/workflows/build.yml)
[![Unit Tests](https://github.com/liberavia/deck-store/actions/workflows/test.yml/badge.svg)](https://github.com/liberavia/deck-store/actions/workflows/test.yml)

DeckStore is a modern, open-source App-Store alternative built for SteamOS devices (like the Steam Deck). 

![DeckStore Home Screen](marketing/home_screen.png)

> **A quick note:** I'm developing DeckStore in my spare time as a personal passion project simply because I felt something like this was missing on my own Steam Deck, and I wanted to support the SteamOS ecosystem. It's currently a one-person endeavor, so development happens whenever I have free time. Feel free to use it, test it, and leave feedback, but please be patient with issues!

## Features

- **SteamOS Native Feel:** Built with the Godot Engine for broad hardware support and tailored specifically to a 1280x800 resolution with full controller mapping.
- **Robust Dependency Management:** Install applications alongside their required extensions cleanly and securely.
- **Steam Integration:** Easily add installed Flatpaks as "Non-Steam Games" directly to your Steam library.
- **Multilingual Support:** Enjoy DeckStore in multiple languages (English, German, French, Spanish, Italian, Polish, Ukrainian).

## Manual Installation

If you want to run or test DeckStore locally:

### Using Godot Engine
1. Clone this repository:
   ```bash
   git clone https://github.com/liberavia/deck-store.git
   cd deck-store
   ```
2. Open the project in the **Godot 4** Editor.
3. Run the project from the editor or export it for Linux/X11.

### Installing a Release (Steam Deck)

To test a compiled release of DeckStore directly on your Steam Deck via the Gaming Mode:

1. Download the latest `deck-store-linux.zip` from the [Releases](https://github.com/liberavia/deck-store/releases) tab.
2. Extract the archive into a folder of your choice (e.g. `~/Games/DeckStore`).
3. **Important (Steam Integration):** Create a text file named `steam_appid.txt` in the exact same folder as the `deck-store.x86_64` executable. Write exactly `480` into this file and save it. This is the AppID for "Spacewar" and is strictly required by the GodotSteam plugin to successfully initialize the Steam API.
4. Open the Steam Client in Desktop Mode and add the `deck-store.x86_64` executable as a "Non-Steam Game".
5. Return to Gaming Mode and select the new shortcut.
6. **Controller Warning:** Before launching the app, go to the game's Controller Settings. Because it uses the Spacewar AppID, Steam will automatically load the official Spacewar controller layout, which will completely break the UI inputs. You must manually change the layout to a standard **"Gamepad"** template.

## Feedback & Contributions

Since this is a personal side-project, I'm currently the main developer working on this in my free time. If you run into bugs or have ideas, feel free to open an issue. If you'd like to submit a Pull Request, please take a quick look at the [Contributing Guidelines](CONTRIBUTING.md) to see how the code is structured and tested.

## License

This project is licensed under the [GNU General Public License v3.0 (GPLv3)](LICENSE).
