# Agent notes

## Release automation

- Pushing to `main` creates or updates the tagpr release pull request.
- `.tagpr` is tag-only: it uses `v`-prefixed SemVer tags and does not update a
  version file, `CHANGELOG.md`, or a GitHub Release itself.
- Merging the tagpr pull request creates the release tag. The same workflow
  checks out that tag and runs `nix run nixpkgs#bun -- x changelogithub` to
  publish the GitHub release notes.
- This repository has no binary release artifacts.
