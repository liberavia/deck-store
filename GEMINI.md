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
*   **Extensions System:** A modular system allows adding functionality via external scripts. Each extension resides in `extensions/<id>/` and contains its own `extension.json`, script, and assets.

## 3. Key Features & Development Focus

*   **Extensions Refactoring (Dec 2025):** Major overhaul of the extension system.
    *   **Bundle Structure:** Extensions are now self-contained folders.
    *   **Dependencies:** Recursive dependency resolution (`dependencies` array in JSON) is implemented. Installing an extension automatically prompts to install missing dependencies via a `DependencyPopup`. Uninstalling warns about breaking dependent extensions.
    *   **Updates:** Robust update mechanism. The system checks for GitHub releases, compares versions, and handles updates by cleanly uninstalling the old version before installing the new one (to bypass Flatpak bundle limitations).
    *   **Progress Reporting:** Real-time feedback from bash scripts to Godot via file polling (`ds_send_progress`).
    *   **Steam Shortcut Manager:** Migrated from a hardcoded binary to a proper Extension. The local binary was removed. `SteamIntegration` and `AddToSteamButton` were updated to rely solely on the extension, prompting for installation if missing.
*   **UI/UX:**
    *   Extensions list now has separate buttons for "Install", "Uninstall", and "Update" (blue).
    *   Sound feedback added for list interactions and popups.
    *   Scrolling issues in lists fixed (`follow_focus`).

## 4. Git Repository Information

*   **Current Branch:** `extract_shortcut_manager` (Merged features likely to be pushed to main soon).
*   **Main Branch:** `main`
*   **Recent Activity:** Complete rewrite of ExtensionsManager, removal of legacy binary code, implementation of dependency management UI.

## 5. Troubleshooting & Known Issues

### 5.1. Update Logic
*   **Issue:** `flatpak install --reinstall` failed for bundles.
*   **Fix:** Updates are now handled by explicit `uninstall` followed by `install` in the extension scripts. The `ExtensionsManager` clears the "update available" flag immediately upon success to reflect changes in the UI.

### 5.2. Missing Extension Dependency
*   **Feature:** If a user clicks "Add to Steam" but the extension is missing, a modal appears.
*   **Implementation:** `add_to_steam_button.gd` checks via `ExtensionsManager` and instantiates `dependency_popup.tscn` if needed.

## 6. Recent Session Log (Dec 31, 2025)

### 6.1. Accomplishments
*   **Refactoring:** Moved all extension logic to `extensions/<id>` structure.
*   **Dependencies:** Implemented recursive dependency resolution (Leaf -> Middle -> Root) and safety checks.
*   **Cleanup:** Removed `bin/steam_shortcut_manager` and Python sources.
*   **UI:** Fixed scrolling, added sounds, improved "Update" visibility.
*   **Testing:** Validated with a set of Dummy extensions (`dummy_core`, `dummy_utils`, `dummy_app`, `dummy_standalone`) which are currently still present in the repo for future testing.

### 6.2. Next Steps
*   **UI Sounds:** The user noted that UI sounds might need further refinement in a separate branch.
*   **Dummy Cleanup:** The dummy extensions (`extensions/dummy_*`) are kept for now but should be removed before a final release.
*   **Push:** Current state is committed and pushed.
--- End of Context from: GEMINI.md ---