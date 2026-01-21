# Contributing to Xbox Controller Mapper

Thank you for your interest in contributing to Xbox Controller Mapper! This document provides guidelines and information for contributors.

## Getting Started

### Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later
- An Xbox Series X|S or DualSense controller for testing

### Setting Up the Development Environment

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/xbox-controller-mapper.git
   cd xbox-controller-mapper
   ```
3. Open `XboxControllerMapper.xcodeproj` in Xcode
4. Build and run the project

## How to Contribute

### Reporting Bugs

Before submitting a bug report:

1. Check the [existing issues](https://github.com/NSEvent/xbox-controller-mapper/issues) to avoid duplicates
2. Collect the following information:
   - macOS version
   - Controller model and connection method (Bluetooth/USB)
   - Steps to reproduce
   - Expected vs actual behavior
   - Screenshots or screen recordings if applicable

Then [open a new issue](https://github.com/NSEvent/xbox-controller-mapper/issues/new) with the bug report template.

### Suggesting Features

Feature requests are welcome! Please:

1. Check existing issues for similar suggestions
2. Open a new issue with the `feature request` label
3. Clearly describe the feature and its use case
4. Include mockups or examples if applicable

### Submitting Code Changes

1. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes:**
   - Follow the existing code style
   - Add comments for complex logic
   - Update documentation if needed

3. **Test your changes:**
   - Test with both Xbox and DualSense controllers if possible
   - Test both Bluetooth and USB connections
   - Verify existing functionality still works

4. **Commit your changes:**
   ```bash
   git commit -m "Add: brief description of your changes"
   ```

5. **Push and create a Pull Request:**
   ```bash
   git push origin feature/your-feature-name
   ```
   Then open a PR on GitHub.

## Code Style Guidelines

### Swift

- Use Swift's standard naming conventions
- Prefer `let` over `var` when possible
- Use meaningful variable and function names
- Keep functions focused and reasonably sized
- Add documentation comments for public APIs

### SwiftUI

- Break complex views into smaller components
- Use `@State`, `@Binding`, `@StateObject` appropriately
- Prefer composition over inheritance

### Project Structure

```
XboxControllerMapper/
├── Models/          # Data models and types
├── Services/        # Business logic and system interaction
├── Views/           # SwiftUI views
└── Utilities/       # Helper functions and extensions
```

## Pull Request Guidelines

- Keep PRs focused on a single feature or fix
- Write a clear description of what the PR does
- Reference any related issues
- Ensure the code builds without warnings
- Test on actual hardware when possible

## Questions?

If you have questions about contributing, feel free to open an issue with the `question` label.

## License

By contributing to Xbox Controller Mapper, you agree that your contributions will be licensed under the same license as the project (see [LICENSE](LICENSE)).
