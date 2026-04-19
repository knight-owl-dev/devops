# validate-action-pins — test fixtures

This directory backs the bats suite at
`tests/bats/images/ci-tools/validate-action-pins.bats`.

## Layout

```text
fixtures/
├── workflows/          input `.yml` files for `check` / `list` / `updates`
└── api/                file:// stand-in for the GitHub REST API
```

Each test sets `GITHUB_API_BASE=file://${FIXTURES_DIR}/api`, so every
`gh_api "/repos/..."` call becomes a file read against this tree.
No network, no rate limit, no flakiness.

## How `api/` mirrors GitHub endpoints

File paths under `api/` map 1:1 onto the URL suffix after
`https://api.github.com`:

| GitHub endpoint                                  | File path                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------------- |
| `GET /rate_limit`                                | `api/rate_limit`                                                          |
| `GET /repos/{o}/{r}/git/ref/tags/{tag}`          | `api/repos/{o}/{r}/git/ref/tags/{tag}`                                    |
| `GET /repos/{o}/{r}/git/ref/heads/{branch}`      | `api/repos/{o}/{r}/git/ref/heads/{branch}`                                |
| `GET /repos/{o}/{r}/git/tags/{sha}`              | `api/repos/{o}/{r}/git/tags/{sha}`                                        |
| `GET /repos/{o}/{r}/tags`                        | `api/repos/{o}/{r}/tags`                                                  |
| `GET /repos/{o}/{r}/compare/{base}...{head}`     | `api/repos/{o}/{r}/compare/{base}...{head}`                               |

The file content is the JSON body GitHub would return. No headers,
no status line — `curl file://...` just reads the file and succeeds
with 200-equivalent semantics (a missing file surfaces as curl
failure, which the tool treats as "ref not found" via its existing
empty-response handling).

A couple of consequences worth knowing:

- **Compare URLs use a literal `...` in the filename.** The compare
  endpoint is `/compare/{base}...{head}`, so the fixture lives at
  `api/repos/{o}/{r}/compare/<40-hex>...<40-hex>` — no extension,
  dots and all. Supported on macOS, Linux, and Git; doesn't play
  well with Windows without WSL.
- **No `.json` extension** on any fixture. The mirror has to match
  the URL exactly, and GitHub's URLs don't include extensions.

## Which repos exist

| Owner/Repo        | Fixtures provided                                                             | Purpose                                                               |
| ----------------- | ----------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `foo/bar`         | `git/ref/tags/v1`, `tags` (list for updates), several workflows               | Canonical tag-pin and upgrade-inventory case                          |
| `foo/annotated`   | `git/ref/tags/v2` (object.type=tag), `git/tags/{sha}` for deref               | Annotated-tag dereference path                                        |
| `foo/br-ok`       | `git/ref/heads/main`                                                          | Branch pin at HEAD (OK)                                               |
| `foo/br-behind`   | `git/ref/heads/main`, `compare/<pinned>...<head>` with `behind_by=3`          | Branch pin 3 commits behind                                           |
| `foo/br-diverge`  | `git/ref/heads/main`, `compare/<pinned>...<head>` with `behind_by=0`          | Branch pin diverged (same `behind_by=0` but distinct SHA)             |
| `foo/nosuch`      | (nothing)                                                                     | Unresolvable-ref path                                                 |

The workflows under `workflows/` pin against these repos by SHA or
symbolic ref to exercise each subcommand branch. If you add a new
case, add the corresponding `api/...` file(s) so the resolver has
something to read.

## Adding a new fixture

1. Pick an owner/repo name (`foo/<something>`) that doesn't collide.
2. Create the workflow in `workflows/<name>.yml` with one or more
   `uses:` lines.
3. For every unique `(owner/repo, ref)` the new workflow pins, add
   the API fixtures the resolver will consult:
   - `check` uses `/git/ref/tags/<ref>` then `/git/ref/heads/<ref>`
     (falls back) and, on annotated tags, `/git/tags/<sha>`.
   - `updates` uses `/tags` for semver-shaped refs and
     `/git/ref/heads/<ref>` for branch-shaped refs.
   - `list --only=...` goes through the same `resolve_ref` as `check`.
4. Write the test(s). Follow the existing convention: one `@test`
   per fixture-plus-assertion pair.
