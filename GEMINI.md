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

## 5. Development Environment Context

*   **Hosts:** The project is developed across two environments:
    *   **Host A:** KDE Neon (User: `andre`, Home: `/home/andre`).
    *   **Host B:** Steam Deck / SteamOS (User: `deck`, Home: `/home/deck`).
*   **Implication:** Hardcoded paths like `/home/deck` must be avoided. Use `$HOME` or Godot's `OS.get_environment("HOME")`. Flatpak `host` permissions are used to bridge the gap.

## 6. Troubleshooting & Known Issues

### 6.1. Update Logic
*   **Issue:** `flatpak install --reinstall` failed for bundles.
*   **Fix:** Updates are now handled by explicit `uninstall` followed by `install` in the extension scripts. The `ExtensionsManager` clears the "update available" flag immediately upon success to reflect changes in the UI.

### 6.2. Missing Extension Dependency
*   **Feature:** If a user clicks "Add to Steam" but the extension is missing, a modal appears.
*   **Implementation:** `add_to_steam_button.gd` checks via `ExtensionsManager` and instantiates `dependency_popup.tscn` if needed.

## 7. Recent Session Log (Jan 03, 2026)

### 7.1. Accomplishments
*   **New Extension:** Created `decky_loader` extension.
    *   Implemented manual "User Mode" installation (no `sudo` required) to bypass SteamOS filesystem locks and password prompts.
    *   Downloads binary directly from GitHub Releases via API parsing in bash.
    *   Creates and manages a systemd user service (`decky-loader.service`) on the host via `flatpak-spawn`.
    *   Robust version checking by parsing the generated service file.
*   **Focus Management:** Fixed an issue where focus was lost after installing extensions via the `AddToSteamButton`. The button now correctly reclaims focus only if it initiated the install.
*   **Cleanup:** Removed all dummy extensions (`dummy_core`, `dummy_utils`, `dummy_app`, `dummy_standalone`) from the repository.
*   **Refactoring:** Moved all extension logic to `extensions/<id>` structure (completed in previous session).

## 8. Recent Session Log (Jan 13, 2026)

### 8.1. Accomplishments
*   **Search View Overhaul:**
    *   **Live Search:** Implemented debounce logic (800ms) to trigger background searches while typing.
    *   **Virtual Keyboard Fixes:** Resolved focus loss issues when using the Steam Deck's virtual keyboard. Standardized manual text handling (Unicode/Backspace) to bypass Godot's `LineEdit` conflicts.
    *   **Input Conflict Resolution:** Added a 300ms input cooldown after search submission to block ghost inputs (e.g., RT trigger axis interpreted as "Page Down").
    *   **UI/UX Enhancements:**
        *   Centered Search Input/Button with square design and application-consistent purple focus styles.
        *   Larger font sizes and increased padding for better legibility on handhelds.
        *   Fixed "B" (ui_cancel) behavior to retain focus on the input field.
        *   Added "No results found" visual feedback.
        *   Dynamic layout: Wrapped the search list in a `MarginContainer` (50px left, 30px right) for a balanced look while maintaining responsiveness.
*   **ProductList Component Fixes:**
    *   **Pagination URL Persistence:** Re-implemented URL parsing to ensure search queries (`q=...`) are preserved when switching pages.
    *   **Ghost Input Protection:** Updated `_unhandled_input` to only process pagination/navigation if the list is visible and either has focus or contains the focused child. This prevents hidden lists (e.g., in other sections) from firing background API requests.
    *   **HomeView Cleanup:** Conditionalized pagination bar visibility to prevent it from appearing on single-line lists (HomeView) after product updates.
    *   **Item Count:** Increased results per page to 24 for better grid filling.

### 8.2. Accomplishments
*   **Search View Overhaul:** Completed (see previous logs).

## 9. Recent Session Log (Feb 14, 2026)

### 9.1. Accomplishments
*   **Update Section Overhaul:**
    *   **Functional Updates:** Implemented a robust update mechanism using `flatpak update --user`.
    *   **Scope Restriction:** Restricted updates exclusively to the `user` scope to ensure compatibility with SteamOS (avoiding read-only filesystem issues and sudo requirements).
    *   **DownloadManager Enhancements:**
        *   **Crash Fix:** Resolved a critical "Nil to float" error by ensuring progress values are always valid numbers.
        *   **Multi-component Progress:** Implemented weighted progress calculation (e.g., handling "1/3" components) to prevent the progress bar from jumping back to 0% between parts.
        *   **Jitter Protection:** Added logic to ensure progress only moves forward.
        *   **Refined Status Parsing:** Robust regex patterns to distinguish between `Downloading` and `Installing`.
    *   **UI/UX Improvements:**
        *   **Installation Feedback:** Added a pulsing animation (modulate alpha) to the progress bar when it reaches 100% during the final "Installing..." phase.
        *   **Dynamic Labels:** Status labels now show "Downloading (X%) [Speed]" and switch to "Installing..." at 100%.
        *   **Select All Toggle:** Replaced the "Select All" checkbox with a modern, dynamic button that toggles between "Select All" and "Deselect All" based on the list state.
        *   **State Persistence:** Refined the list refresh logic to preserve manual selections after a "Refresh List" action.

### 9.2. Next Steps
*   **Batch Verification:** Final verification of large batch updates on hardware.
*   **Steam Integration:** Verify that shortcuts remain functional/updated after a flatpak update.
*   **General Polish:** Address any remaining minor UI inconsistencies in other views (e.g., Settings/Extensions) to match the new standards set in Search and Updates.
*   **Cleanup:** Remove any remaining legacy debugging logs or unused scenes.

## 10. Recent Session Log (Feb 15, 2026)

### 10.1. Accomplishments
*   **Navigation Standardization:**
    *   **Unified "Go Back" Logic:** Standardized the behavior of the "B" button (ui_cancel/go_back) across all views.
    *   **Hierarchical Focus Exit:** Pressing "B" in any list or section-specific UI now consistently moves focus up to the top navigation bar.
    *   **Global "Go Home" Shortcut:** Pressing "B" while the top navigation bar is focused (on any section except Home) now triggers an immediate switch back to the Home section.
*   **Dynamic Footer Bar (Action Guide):**
    *   **Context-Sensitive Prompts:** Implemented a new `FooterBar` component at the bottom of the screen that dynamically displays available controller actions based on the current focus.
    *   **Custom Action Labels:** Replaced generic "Open" labels with context-accurate ones like "App Details," "Go to Details," "Select/Unselect App," "Manage Extension," and "Start Search."
    *   **Pagination Awareness:** Added "L2 / R2" prompts (Previous/Next Page) that only appear when a `ProductList` with multiple pages is focused.
    *   **Real-time Updates:** Connected focused item signals (like `pressed` and `status_changed`) to ensure the footer bar reflects UI state changes immediately (e.g., toggling "Select All" or individual updates).
*   **Bug Fixes & Refinements:**
    *   **Input Conflict Resolution:** Fixed issues in `Search` and `Extensions` views where input consumption was blocking the global "Go Home" logic.
    *   **Robust Item Detection:** Implemented script-path and name-based detection in `main.gd` to ensure correct prompts are shown for custom list items (`InstalledAppItem`, `UpdateItem`, etc.).
    *   **UI Polish:** Right-aligned the footer actions and added vertical margins for a more modern, spacious look consistent with SteamOS aesthetics.

### 10.2. Next Steps
*   **Navigation Refinements:** Continue polishing focus behavior and transitions.
*   **Analog Input Deadzones:** Investigate and calibrate joystick deadzones to prevent drift and accidental navigation.
*   **Visual Icon Integration:** Consider replacing simulated text-based button icons (A/B/X/Y) with actual SVG gamepad icons for a more polished look.

## 11. Recent Session Log (Feb 22, 2026)

### 11.1. Accomplishments (Bazzite Compatibility)
*   **Enhanced SteamOS/Bazzite Support:**
    *   **Remote Management:** Implemented `_ensure_user_remote_exists()` in `main.gd` to automatically verify and add the Flathub user-level remote if missing. This is critical for systems like Bazzite where Flathub might only be a system-level remote by default.
    *   **Installation Logic:** Updated `DownloadManager.gd` to explicitly specify the remote name (`flathub`) during user-scope installations. This prevents ambiguity when an app exists in both system and user remotes.
    *   **Update Discovery:** Broadened `updates_view.gd` to check for updates across both system and user remotes, ensuring available updates are correctly detected regardless of how the remote was added.
*   **Progress Tracking Improvements:**
    *   **Multi-Step Progress:** `DownloadManager` now correctly parses and reports "Step X/Y" information (e.g., "Step 2/6") from Flatpak logs.
    *   **Dynamic Labels:** Updated `details_view.gd` to show these steps in the UI (e.g., "Installing... (Step 3/5)"), providing much clearer feedback for batch installations or complex updates.
    *   **Regex Optimization:** Refined Flatpak output parsing regex to be more robust across different locale-specific outputs and Flatpak versions.
*   **Performance & Stability:**
    *   **Console Logging Optimization:** `ExtensionsManager.gd` now filters out redundant Flatpak progress bar lines and truncates large script outputs to prevent console spam and improve performance.
    *   **Refresh Logic:** `installed_view.gd` now includes a `_refresh_pending` flag and an increased cooldown (300s) to prevent overlapping or excessive automatic refreshes.
*   **Engine Update:**
    *   **Godot 4.6:** Updated project settings to reflect usage of Godot 4.6 features and ensured basic compatibility settings (mesh instance skeleton defaults).

## 13. Recent Session Log (Feb 22, 2026 - Part 3)

### 13.1. Accomplishments (Controller Glyphs & Persistent UI)
*   **Dynamic Controller Glyph System:**
    *   Created a library of SVG gamepad icons for both Xbox/Steam Deck and PlayStation styles.
    *   Implemented `ControllerManager` autoload to automatically detect the active controller type based on input device names and provide appropriate glyph paths.
    *   Created a reusable `GlyphDisplay` component that updates its texture dynamically and provides visual feedback (scale/glow) when its associated button is pressed.
    *   Updated the `FooterBar` to use high-quality SVGs instead of text-based button labels.
*   **Enhanced Header & Pagination UI:**
    *   Integrated L1/R1 glyphs into the main navigation tab bar with press-feedback that highlights the target section button.
    *   Added L2/R2 glyphs to both top and bottom pagination bars in `ProductList`, providing visual cues for quick page switching.
    *   Implemented synchronized button highlighting in `ProductList` when the corresponding trigger is pressed.
*   **Persistent Footer Bar & Details Integration:**
    *   Restructured `main.tscn` to move the `FooterBar` into a dedicated high-priority `CanvasLayer` (layer 1), ensuring it remains visible and fixed even when the main view slides away.
    *   Updated `DetailsView` integration to correctly report and display its own context-aware actions (e.g., "Zoom Screenshot", "Add to Steam", "Show Reviews") in the global footer.
*   **Advanced Screenshot Navigation:**
    *   Refactored `DetailsView` and `ScreenshotZoomPopup` to allow full navigation of the screenshot gallery from the zoomed view.
    *   Implemented L2/R2 navigation in the zoom popup with a sliding animation effect similar to the main section transitions.

### 13.2. Next Steps
*   **Completed:** Analog Input Deadzones, Animation Polish, and Search Layout Refinement have been addressed.

## 14. Recent Session Log (July 20, 2026)

### 14.1. Accomplishments
*   **Controller Glyph Rework:** Implemented comprehensive controller glyph support, adding SVG icons for Xbox/PS controllers, and a `ControllerManager` with `GlyphDisplay`.
*   **Virtual Keyboard Stabilization:** Improved and stabilized virtual keyboard handling.
*   **Navigation Fixes:** Resolved double-jumps in the product list and implemented jumping back to the search box/category selection from lists.

### 14.2. Next Steps
*   **Mouse Control Implementation:** Currently working on the `navigation` branch to implement proper mouse control ("Maussteuerung").

## 15. Recent Session Log (July 20, 2026 - Part 2)

### 15.1. Accomplishments (Settings MVP & Architecture Refactoring)
*   **Settings Modal MVP:**
    *   Implemented `SettingsManager` Autoload to persist user settings in `~/.deck-store/settings.json`.
    *   Added dynamic `settings_modal.tscn` to toggle UI sounds and Automatic Refresh.
    *   Fixed padding (`MarginContainer`) and visual bugs where the `ScrollContainer` masked the focus ring of form elements.
    *   Fixed a visual bug in `installed_view.gd` where the cooldown progress bar kept updating even if auto-refresh was disabled.
*   **Publishing / Native Execution Architecture:**
    *   Created `SystemUtils` Autoload to abstract command execution across different runtimes.
    *   The app now safely detects if it runs in a Flatpak sandbox (`/.flatpak-info`). If yes, it uses `flatpak-spawn --host`; if no (e.g. running natively via Steam), it uses the host's `/usr/bin/flatpak` directly.
    *   Refactored `DownloadManager`, `main.gd`, and `SteamIntegration.gd` to completely replace hardcoded `flatpak-spawn` calls with `SystemUtils`.
    *   Created `TESTING_ON_STEAM_MACHINE.md` outlining the Linux/X11 export process for pristine SteamOS testing.

### 15.2. Next Steps
*   **Verify Native Build:** Test the exported `.x86_64` binary on the pristine Steam Machine as a Non-Steam Game to verify the `SystemUtils` wrapper correctly discovers and manages Flatpaks outside the Godot sandbox.
*   **GodotSteam Integration:** Once native execution is verified, integrate the GodotSteam plugin to utilize the native Steamworks floating keyboard (`Steam.showFloatingGamepadTextInput()`) and resolve the Wayland focus issues during search.
--- End of Context from: GEMINI.md ---