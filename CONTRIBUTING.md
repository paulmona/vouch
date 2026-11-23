# Contributing

Thanks for helping. Vouch is small, and changes go through pull requests.

## Before you open a PR

- **One change per PR**, with a description that says why.
- **Sign off every commit** (`git commit -s`, see "Licence and sign-off").
- **Run the tests for every part you touched** (see "Running things locally"):
  server, broker and app.
- **CI must pass.** The `checks` job runs the server's lint, typecheck and tests,
  the broker's lint, tests and audit,
  the app's format, analyze and tests, a check that the generated API client
  matches the contract, a breaking-change check on the contract, a secrets
  scan, and a check that every commit is signed off.
- **Never commit secrets or signing material**: Firebase files
  (`google-services.json`, `GoogleService-Info.plist`), service-account JSON,
  keystores, `key.properties`, `.env` files. They are git-ignored; keep it so.

## The API contract

`api/openapi.yaml` is the contract between the app and the server. Change it
only by PR, regenerate the app's client in the same PR
(`app/tool/generate_api.sh`), and expect the breaking-change check to fail on
anything an older app couldn't handle. A deliberate break needs the
`api-breaking` label and a sentence on why it is safe.

## Running things locally

- Server: `cd server && npm ci && npm test`. Node 24.
- Broker: `cd broker && uv run --frozen pytest -q`. Python 3.12 or 3.13 and `uv`.
  The fill tests drive a real browser: they need `google-chrome` on the path
  and are skipped without it.
- App: Flutter (version pinned in CI). `cd app && flutter test`.
- A software phone for testing without a device: `server/tools/fake-device.ts`
  (see `server/README.md`).

## Maintainers

The GitHub settings the workflows rely on, and how a release is cut, are in
[docs/maintaining.md](docs/maintaining.md).

## Licence and sign-off

By contributing you agree your contribution is licensed under the Apache
License 2.0, the same as the project.

Every commit in a pull request must be signed off. A sign-off is one line at
the end of the commit message:

    Signed-off-by: Your Name <you@example.com>

`git commit -s` adds it for you. With it you state that you wrote the change,
or otherwise have the right to submit it under the project's licence, as set
out in the [Developer Certificate of Origin](https://developercertificate.org/).
Use your real name. CI fails a pull request that has a commit without the line
(merge commits are not checked); `git rebase --signoff main` adds it to every
commit on a branch.
