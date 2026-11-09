# Magpie for Apple platforms

SwiftUI client for the magpie gateway `/me` page. `README.md` describes usage and the layout.

## Build and test

- Run `make generate` after you change `project.yml`. `Magpie.xcodeproj` is generated and not tracked.
- Run `make lint` and `make test` before you commit. `make check` runs lint, build, and test.
- UI tests need a gateway: `make ui-test MAGPIE_TEST_GATEWAY_URL=... MAGPIE_TEST_GATEWAY_KEY=...`. Use `make demo-gateway` (key `sk-magpie-key-demo`) for populated charts.
- `.github/workflows/ci.yml` runs `make lint`, `make build`, and `make test` on a GitHub-hosted macOS runner for every push to `master` and every pull request. The workflow selects the Xcode version from `options.xcodeVersion` in `project.yml`; to change the version, edit `project.yml`, not the workflow.

## Privacy

This repository is public. Do not put any of the following in tracked files, commit messages, issues, or pull requests unless the user explicitly allows that one value:

- the address of a gateway instance we run, or any other internal hostname, IP address, or URL;
- gateway keys, Apple Developer team IDs, or other account identifiers;
- responses captured from a gateway we run in production; fixtures and screenshots come from `scripts/demo_gateway.py` or a local development gateway with throwaway data;
- the model or name of a physical device used for testing.

Per-developer values belong in `Config/Local.xcconfig`, which Git ignores. Use `https://magpie.example.com` and `sk-magpie-key-...` as placeholders.

## Conventions

- Commit messages follow Conventional Commits: `<type>(<scope>): <description>`.
- Repository text (code, comments, commit messages, README) is English. The app UI is Chinese.
