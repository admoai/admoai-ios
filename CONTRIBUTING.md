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

2. **Verify code formatting:**
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

Formatting is enforced in CI by [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
(the version is pinned in `.github/workflows/ci.yml`; rules, and why some defaults are off,
in `.swiftformat`). Before pushing:
```bash
brew install swiftformat            # once
swiftformat Sources Tests Tools     # fix
swiftformat Sources Tests Tools --lint   # what CI runs
```

## When the API check fails

`api/AdMoai.api.txt` is the module's public API, one symbol per line (path, kind, declaration),
and CI (`Public API check`) fails when the code no longer matches it. That is deliberate: a
removed or changed public symbol breaks every integrator's build on their next package update,
so the change has to appear as a diff in the PR, where a reviewer who does not read Swift can
still see it.

1. Run `Tools/api.sh` and commit `api/AdMoai.api.txt`. The declarations are spelled by the
   compiler, so the baseline is generated with the Xcode CI pins (`XCODE_API_VERSION` in
   `.github/workflows/ci.yml`). With a different local Xcode, download the `api-baseline`
   artifact from the failing run and commit that file instead.
2. Read the diff; the CI log and job summary also list what
   `swift package diagnose-api-breaking-changes` calls breaking. Only `+` lines is a `feat:`.
   Any `-` or changed line is a **breaking change**: mark the PR `feat!:` (or add a
   `BREAKING CHANGE:` footer) so release-please bumps the major, and say what integrators must
   change.
3. If the surface changed by accident (something that should be `internal`), fix the access
   level instead of updating the baseline.

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

