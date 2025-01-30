# Release Process

This document outlines the process for creating new releases of HAM.

## Version Numbering

We follow [Semantic Versioning](https://semver.org/):
- **MAJOR** version for incompatible config changes
- **MINOR** version for backwards-compatible functionality
- **PATCH** version for backwards-compatible bug fixes

## Release Process

1. Create a Pull Request
   - Create a new branch for your changes
   - Make necessary updates (including version in Dockerfile if needed)
   - Submit PR to main branch
   - Wait for tests to pass and review to be completed
   - Merge PR to main

2. Create and Push Tag
   ```bash
   # For version 1.2.3
   git checkout main
   git pull
   git tag -a v1.2.3 -m "Release v1.2.3"
   git push origin v1.2.3
   ```

   The tag push will automatically trigger:
   - Build and test workflow
   - Docker image build for all platforms
   - Push to container registry with appropriate tags

## Docker Tags Created

The workflow automatically creates multiple tags:
- `1.2.3` - Full version (from semver pattern)
- `1.2` - Minor version
- `latest` - On tagged releases
- `sha-<commit>` - Git SHA for every push

## Verifying the Release

1. Check GitHub Actions
   - Verify the workflow completed successfully
   - Check that all platforms were built correctly

2. Check Container Registry
   - Verify new tags are present
   - Check multi-platform support:
     ```bash
     docker buildx imagetools inspect ghcr.io/minvs1/ham:1.2.3
     ```

3. Test the Release
   ```bash
   docker pull ghcr.io/minvs1/ham:1.2.3
   ```
