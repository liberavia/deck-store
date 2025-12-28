# Project Analysis: DeckStore

This document summarizes the key aspects of the DeckStore application based on an initial analysis of the codebase.

## 1. High-Level Overview

*   **Purpose:** A Godot-based App-Store for SteamOS devices, designed to find and install Flatpak packages from Flathub.
*   **Target Platform:** Steam Deck, as indicated by the 1280x800 resolution and extensive joypad/controller input mapping.
*   **Core Technology:** Built with the Godot Engine (v4.4) using the GL Compatibility renderer for broad hardware support.

## 2. Architecture and Code Structure

*   **Main Entry Point:** The application starts with the `main.tscn` scene.
*   **Autoload Singletons:** Core functionality is managed by globally accessible singleton scripts. These are critical components:
    *   `DownloadManager`: Manages file downloads (likely for Flatpak apps and metadata).
    *   `SteamIntegration`: Handles integration with the Steam client (e.g., via Steamworks API).
    *   `OdrsRatingsCache`: Caches app ratings from the Open Desktop Rating Service (ODRS).
    *   `ExtensionsManager`: Manages a system of extensions for the app.
    *   `GlobalBackgroundShader`: Provides a global background visual effect.
*   **UI Structure:** The UI is modular, broken into different "sections" and components, such as:
    *   `home_view.tscn`
    *   `details_view.tscn`
    *   `product_list.tscn`
    *   `reviews_popup.tscn`
*   **Python Integration:** A Python script, `steam_shortcut_manager.py`, is used to manage Steam shortcuts. It is packaged into an executable using PyInstaller, as indicated by the `.spec` file.

## 3. Key Features & Development Focus

*   **Steam Shortcut Management:** A primary feature is the ability to add/remove shortcuts for installed Flatpak applications directly in the Steam client.
*   **Extensions System:** The application features a nascent extension system. The `steam_shortcut_manager` is being refactored to be the first official extension, as seen in the `extract_shortcut_manager` branch.
*   **Active Development:** Recent commits show a focus on:
    *   Refactoring and modularizing code (e.g., "Extract Home-View into seperate section").
    *   UI/UX polishing ("Polish details navbar").
    *   Bug fixing, including threading issues related to installations.

## 4. Git Repository Information

*   **Current Branch:** `extract_shortcut_manager`
*   **Main Branch:** `main`
*   **Recent Activity:** Refactoring of the shortcut manager, UI enhancements, and the creation of an extensions system.

## 5. Troubleshooting

This section documents issues encountered and their resolutions.

### 5.1. `flatpak: command not found` Error

*   **Symptom:** Scripts executed by the `ExtensionsManager` fail with errors like `flatpak: command not found`.
*   **Root Cause:** The DeckStore application itself is running as a Flatpak. When Godot's `OS.execute` function runs a script, that script runs inside the DeckStore's own sandbox, which does not have direct access to the host system's `flatpak` command.
*   **Resolution:** The script was modified to use `flatpak-spawn --host` for all `flatpak` and `flatpak-builder` commands. This is the standard and correct way for a Flatpak application to interact with the host's Flatpak daemon.

### 5.2. Update Fails to Find Download URL

*   **Symptom:** The extension update process fails with `ERROR: Could not find download URL for asset 'io.github.liberavia.steamshortcutmanager.zip' in the latest release.`
*   **Root Cause:** The script was hardcoded to look for a specific `.zip` file in the GitHub release's assets. An API check revealed that the target repository's releases do not contain any assets, only source code `zipball` and `tarball` links.
*   **Resolution:** The update script was modified to download the source code using the `zipball_url` provided by the GitHub API. The logic was also updated to handle the folder structure created when extracting a GitHub source archive.