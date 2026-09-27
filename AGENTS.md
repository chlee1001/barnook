# Repository workflow

This is an independent Apache 2.0 derivative of ronny/ellipsis. Keep the original license, copyright and attribution, and mark modifications to inherited files. Do not commit credentials or Sparkle private keys.

## Changes and reviews

- Branch from `main`; make one logical change per commit. Use a conventional-commit subject and a short why-focused body. Add only applicable lore trailers (`Lore-id`, `Constraint`, `Rejected`, `Confidence`, `Scope-risk`, `Reversibility`, `Tested`, `Not-tested`). Never claim a test was run when it was not.
- Open PRs against `main`. Explain what changed, why, actual verification, limitations, and an honest risk classification. Feature, signing, updater and release changes are high-risk; request independent review before merging. Do not present self-review as independent approval. Do not rewrite public history to make a PR appear reviewed.
- Run `swift test` and `swift build --build-tests`; hosted CI runs both on `xcode-27` and ShellCheck on Ubuntu. VM tests require Tart and must be reported separately. Changes to release scripts require a dry preflight, shell syntax checks, and artifact inspection before publishing.

## Releases

- Publish only from a clean `main` at `origin/main` after the PR is merged and checks/review are complete. Run `scripts/release.sh X.Y.Z` to prepare and inspect the signed, notarized ZIP and signed Sparkle appcast. Then run `scripts/publish.sh X.Y.Z` to tag and upload. `mise run release X.Y.Z` combines them.
- Never tag or publish before the build and signing checks succeed. Keep the Developer ID certificate, notarytool credentials and EdDSA private key out of Git. The app's `SUPublicEDKey` must match the private key used for the appcast. Preserve the bundled Apache and Sparkle licenses.
