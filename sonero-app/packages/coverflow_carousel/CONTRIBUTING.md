# Contributing to Coverflow Carousel

Thank you for your interest in contributing to Coverflow Carousel! Community contributions help make this package more robust, efficient, and feature-rich.

By participating in this project, you agree to abide by our code of conduct and contribution guidelines.

## How Can I Contribute?

### Reporting Bugs
* Search the existing Issues to see if the bug has already been reported.
* If not, open a new Issue, describing the problem clearly.
* Include steps to reproduce, the expected behavior, screenshots or screen recordings (if applicable), and your environment details (output of `flutter doctor` and your package version).

### Suggesting Enhancements
* Open an Issue to discuss the enhancement before writing any code.
* Explain the use case, how it benefits other users, and how you envision the implementation.

### Pull Requests
* Keep pull requests focused on a single change, fix, or feature.
* Do not update the version number in `pubspec.yaml` or write release notes in `CHANGELOG.md`. The maintainers will handle versioning and releases.
* Ensure all tests pass and static analysis is fully clean.

---

## Development Setup

Follow these steps to set up your local development environment:

1. **Fork and Clone** the repository:
   ```bash
   git clone git@github.com:YOUR_USERNAME/coverflow_carousel_package.git
   cd coverflow_carousel_package
   ```

2. **Get Dependencies** for both the main package and the example project:
   ```bash
   # Main package
   flutter pub get

   # Example project
   cd example
   flutter pub get
   cd ..
   ```

3. **Run the Example App** to verify the baseline works:
   ```bash
   cd example
   flutter run
   ```

---

## Quality Standards & Verification

Before submitting a Pull Request, you must verify that your changes adhere to our quality and formatting standards. The CI pipeline will automatically run these checks on your PR.

### 1. Code Formatting
All Dart files must be formatted using the standard formatter:
```bash
dart format .
```
To verify formatting without modifying files (matching the CI check):
```bash
dart format --output=none --set-exit-if-changed .
```

### 2. Static Analysis
Verify that both the core package and the example application contain zero warnings, lints, or static analysis errors:
```bash
# Analyze main package
flutter analyze

# Analyze example app
cd example
flutter analyze
cd ..
```

### 3. Automated Tests
Ensure that all unit and widget tests run and pass successfully:
```bash
flutter test
```

---

## Pull Request Guidelines

1. **Create a Branch**: Always work on a descriptive branch name (e.g., `fix/overlay-drift` or `feature/custom-curves`).
2. **Write Clean Code**: Follow the official [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style). Keep implementation clean and commented where necessary.
3. **Write Tests**: If you are fixing a bug or adding a feature, please include corresponding unit or widget tests inside the `test/` directory to prevent future regressions.
4. **Link Issues**: In your pull request description, link to any issues resolved by the PR (e.g., `Fixes #123`).
