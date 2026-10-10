# aav2-module-example: subfinder

A reference **worker module** for Attack Atlas (aav2). It wraps [ProjectDiscovery subfinder](https://github.com/projectdiscovery/subfinder) for passive subdomain enumeration.

> **Status: example, draft format.** The aav2 plugin architecture (worker modules, a GitHub-based registry, multiple module runtimes) is being designed now. This repo is the concrete example that design is built against. The manifest is `schema_version: 0` and **will change** when the spec is signed off.

## What a module is

A module packages everything a worker needs to run one tool, so that tool logic can be updated and redeployed **without rebuilding or redeploying the worker runtime**:

| Piece | File | How the worker uses it |
|---|---|---|
| Manifest | [`module.yaml`](module.yaml) | Name, version, runtime, command, arguments, permissions and resources. This is the contract between the module and the worker. |
| External binary | `binaries:` in the manifest | Fetched from the **upstream release URL**, with the archive sha256 and the extracted-binary sha256 both verified, then installed into the worker's private tool directory. **The bundle never contains the binary.** |
| Parser | [`parser/subfinder.lua`](parser/subfinder.lua) | Runs in the worker's sandboxed **Lua** runtime (no `io`/`os`) and turns raw tool output into aav2's normalized document (`assets`, `edges`, `parse_skipped`). Other runtimes, such as `wasm`, use the same contract. |
| Config files | [`config/`](config) and `configs:` in the manifest | Written to a per-task, read-only tmpfs path before the tool runs, then removed. `source: module` files ship in the bundle. `source: orchestrator` files (anything that can hold secrets, like subfinder's API keys) are managed by an aav2 admin in the orchestrator (encrypted at rest, never echoed back by the API) and delivered only to the worker running the module. They override the bundled empty default. **Never commit secrets to a module repo.** |

## Registry model: GitHub

- **One repo per module.** A module version is a **git tag `vX.Y.Z`** equal to `module.version`.
- Each tag publishes a **GitHub release** containing a deterministic bundle (`aav2-module-subfinder-X.Y.Z.tar.gz`) and its `.sha256`. See [`.github/workflows/release.yml`](.github/workflows/release.yml).
- An aav2 admin **allowlists the repo** and **pins an exact version** (per worker group if needed). Workers pull the pinned bundle **directly from GitHub**, verify its sha256 against the pin, and swap it in. Rolling back means re-pinning the previous version. Signing and attestation may be added later.

## Develop

```sh
lua5.4 tests/run.lua            # parser tests (Lua 5.3+; tests/json.lua stands in for the host API)
scripts/bundle.sh 1.0.0         # build dist/aav2-module-subfinder-1.0.0.tar.gz + .sha256
```

### Parser contract

```lua
-- input : raw tool output as ONE string (JSON lines plus log noise, ANSI escapes, CRLF)
-- output: { assets = { {type="subdomain", fqdn="api.example.com"}, ... },
--           edges = {}, parse_skipped = <lines that yielded no asset> }
-- host  : aav2.json_decode(s) -> table|nil   (provided by the worker runtime)
```

The parser must be a **pure function**. It doesn't use I/O or OS calls, and it doesn't write globals. The test suite runs it in a restricted environment to enforce that.

### Rules the aav2 worker still enforces

- The command template must carry `-duc` (the update check is disabled), and update flags are rejected (aav2 #222).
- Argument values starting with `-` are rejected at run time, to block argv flag injection (aav2 #227).
- Modules run with **zero Linux capabilities** and can't widen the `permissions:` they declare.

## Release

```sh
# bump module.version in module.yaml, commit, then:
git tag v1.0.0 && git push origin v1.0.0
```
