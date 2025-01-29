# Release Process

This document outlines the process for creating new releases of HACS Plugins.

## Version Numbering

We follow [Semantic Versioning](https://semver.org/):
- **MAJOR** version for incompatible config changes
- **MINOR** version for backwards-compatible functionality
- **PATCH** version for backwards-compatible bug fixes

## Creating a Release

1. Update Version
   ```bash
   # Update HACS_VERSION in Dockerfile if needed
   ENV HACS_VERSION="1.34.0"
   ```

2. Commit Changes
   ```bash
   git add Dockerfile
   git commit -m "chore: update HACS version to 1.34.0"
   ```

3. Create and Push Tag
   ```bash
   # For version 1.2.3
   git tag -a v1.2.3 -m "Release v1.2.3"
   git push origin v1.2.3
   ```

4. Create GitHub Release
   - Go to GitHub Releases page
   - Click "Create a new release"
   - Select the tag you just pushed
   - Fill in the release notes (see template below)
   - Click "Publish release"

## Docker Tags Created

The workflow will automatically create multiple tags:
- `1.2.3` - Full version
- `1.2` - Minor version
- `latest` - Latest stable release (main branch)

## Release Notes Template

```markdown
## Release v1.2.3

### 🚀 New Features
- List new features

### 🐛 Bug Fixes
- List bug fixes

### 📝 Documentation
- List documentation changes

### 🔧 Maintenance
- List maintenance updates

### 🏗️ Dependencies
- List dependency updates (e.g., HACS version)
```

## Verifying the Release

1. Check GitHub Actions
   - Verify the workflow completed successfully
   - Check that all platforms were built

2. Check Container Registry
   - Verify new tags are present
   - Check multi-platform support:
     ```bash
     docker buildx imagetools inspect ghcr.io/minvs1/hacs-plugins:1.2.3
     ```

3. Test the Release
   ```bash
   # Pull and test the new version
   docker pull ghcr.io/minvs1/hacs-plugins:1.2.3
   # Run tests
   docker build -f Dockerfile.test -t hacs-plugins-tests .
   docker run --rm hacs-plugins-tests
   ```

## Rolling Back a Release

If issues are found with a release:

1. Remove the problematic tag
   ```bash
   git tag -d v1.2.3
   git push --delete origin v1.2.3
   ```

2. Delete the GitHub Release
   - Go to the Releases page
   - Delete the problematic release

3. Delete container images
   - Remove the problematic tags from the container registry

4. Create a new patch release with fixes

## Common Issues

### Missing Platforms
If certain platforms are missing from the release:
1. Check the build logs for platform-specific errors
2. Verify QEMU is working correctly in the workflow
3. Consider platform-specific tests if needed

### Version Conflicts
If you encounter version conflicts:
1. Ensure all version numbers match (git tag, release title, HACS version)
2. Check that the release tag follows semantic versioning
3. Verify the version hasn't been used before

### Failed Tests
If tests fail during release:
1. Run tests locally to reproduce the issue
2. Check if the failure is platform-specific
3. Verify test dependencies are correct
4. Fix issues and create a new release
