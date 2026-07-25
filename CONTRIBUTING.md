# Contributing to DeckStore

First off, thank you for considering contributing to DeckStore! We aim to build a strong community to improve this tool for everyone.

## Git & Branching Strategy

- **`main`**: The primary branch. It must always be stable.
- **Feature Branches**: Please create a new branch for every feature or bug fix. 
  - Naming convention: `feature/your-feature-name` or `bugfix/your-bugfix-name`
  - When finished, submit a Pull Request (PR) to the `main` branch.

## Pull Requests & Automated Tests

All Pull Requests are subject to automated checks:
1. **Build Check**: Ensures the Godot project successfully builds without script errors.
2. **Unit Tests**: We use GUT (Godot Unit Test) for our test suite. Your PR must pass all existing tests. If you are adding a major feature, please include accompanying tests.

## Versioning & Codenames

We use a custom, chronological versioning schema combined with paradoxical codenames.

**Format**: `YY.MM.<Release-Number>-<Codename>`
*Example: `26.07.1-SilentSound`*

### Codename Rules
A codename must be an **alliterative oxymoron** (a paradoxical allegory where both words start with the same letter).
Examples:
- `SilentSound`
- `DarkDaylight`
- `ConstantChange`
- `FierceFragility`
- `ChaoticCalm`
- `KnownKnot`
- `LivingLoss`

When a new version is built via GitHub Actions, a Release is automatically generated based on the tag.

## Code Standards
- Adhere to the existing Godot UI architecture (`ui/components`, `ui/views`, `ui/modals`).
- Keep controllers (gamepads) in mind for all new UI additions (ensure focus layers and B-button "go back" behavior are respected).
- We use GDScript 2.0 features (Godot 4.x). Ensure static typing is used wherever reasonable.
