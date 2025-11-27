# Contributing to AdMoai iOS SDK

Thank you for considering contributing to the AdMoai iOS SDK! This document outlines the process and guidelines for contributing.

## Development Workflow

1. **Fork the repository** and clone it locally
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```
3. **Make your changes** following our coding standards
4. **Test your changes** thoroughly
5. **Commit using Conventional Commits** (see below)
6. **Push to your fork** and create a Pull Request

## Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/) for automated changelog generation and semantic versioning.

### Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

- **feat**: A new feature (triggers MINOR version bump)
- **fix**: A bug fix (triggers PATCH version bump)
- **perf**: Performance improvements (triggers PATCH version bump)
- **refactor**: Code changes that neither fix bugs nor add features
- **chore**: Changes to build process, dependencies, or tooling
- **docs**: Documentation only changes
- **style**: Code style changes (formatting, missing semicolons, etc.)
- **test**: Adding or updating tests
- **build**: Changes to build system or dependencies
- **ci**: Changes to CI/CD configuration

### Breaking Changes

To indicate a breaking change (triggers MAJOR version bump):

```
feat!: remove deprecated API methods

BREAKING CHANGE: The old `requestAd()` method has been removed. Use `requestAds()` instead.
```

### Examples

**Good commit messages:**

```bash
feat: add video ad support
fix: resolve memory leak in tracking
perf: optimize ad request caching mechanism
docs: update README with installation steps
refactor: simplify decision request builder API
test: add unit tests for custom targeting
chore: update Swift Package Manager dependencies
```

**Bad commit messages:**

```bash
Update code                    # Too vague
Fixed bug                      # Missing type and description
FEAT: Add feature             # Type should be lowercase
feat: Added new feature.      # Description should be imperative mood
```

## Testing Requirements

Before submitting a PR:

1. **Run all tests:**
   ```bash
   swift test
   ```

2. **Run the demo app:**
   ```bash
   cd Examples/Demo
   open Demo.xcodeproj
   # Build and run in Xcode
   ```

3. **Verify code formatting:**
   ```bash
   swift format lint --recursive .
   ```

4. **Test on multiple platforms:**
   - iOS (Simulator and device)
   - macOS (if applicable)

5. **Build documentation:**
   ```bash
   swift package --allow-writing-to-directory ./docs \
     generate-documentation --target AdMoai \
     --output-path ./docs \
     --transform-for-static-hosting \
     --hosting-base-path admoai-ios
   ```

## Pull Request Guidelines

### PR Title

PR titles must follow Conventional Commits format (enforced by CI):

```
feat: add video ad support
fix: resolve memory leak in ad tracking
docs: update README with installation steps
```

### PR Description

Include:
- **What**: Summary of changes
- **Why**: Motivation and context
- **How**: Technical approach (if non-trivial)
- **Testing**: How you tested the changes
- **Screenshots**: If UI changes (from demo app)
- **Breaking Changes**: If applicable

### Checklist

- [ ] Code follows Swift style guidelines
- [ ] Self-reviewed the code
- [ ] Commented complex/non-obvious code
- [ ] Updated documentation (if needed)
- [ ] Added/updated tests
- [ ] All tests pass locally
- [ ] No compiler warnings
- [ ] PR title follows Conventional Commits

## Code Style

We follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/):

- **Naming**:
  - Types: `PascalCase`
  - Functions/variables: `camelCase`
  - Constants: `camelCase` (Swift convention)
  - Files: `PascalCase.swift`
- **Line length**: 120 characters max
- **Indentation**: 4 spaces (no tabs)
- **Access control**: Use explicit access control (`public`, `internal`, `private`)

Use SwiftFormat for consistent formatting:
```bash
swift format --recursive .
```

## Swift Package Manager

This SDK uses Swift Package Manager:

- **Package.swift**: Main package definition
- **Dependencies**: Keep to minimum, prefer standard library
- **Versioning**: Uses git tags (v0.1.0, v0.2.0, etc.)

## Security

If you discover a security vulnerability:

1. **DO NOT** open a public issue
2. Email security@admoai.com with details
3. Wait for acknowledgment before disclosing publicly

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

## Need Help?

- **Documentation**: [README.md](README.md)
- **API Docs**: https://admoai.github.io/admoai-ios/documentation/admoai
- **Issues**: [GitHub Issues](https://github.com/admoai/admoai-ios/issues)
- **Discussions**: [GitHub Discussions](https://github.com/admoai/admoai-ios/discussions)

---

Thank you for contributing!

