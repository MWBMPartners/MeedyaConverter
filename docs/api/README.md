# MeedyaConverter API documentation

This directory documents MeedyaConverter's two API surfaces as OpenAPI 3.1
specs, plus a self-hostable Swagger UI to browse them interactively.

```
docs/api/
├── meedya-convert-api.yaml   # the meedya-convert CLI, modelled as an OpenAPI doc
├── meedya-http-api.yaml      # the experimental HTTP server (APIServer) — see below
├── swagger-ui/
│   └── index.html            # static Swagger UI, no build step, no server code
└── README.md                 # this file
```

## What each spec covers

### `meedya-convert-api.yaml` — the CLI

Documents the actual `meedya-convert` command-line tool
(`Sources/meedya-convert/**`): its six subcommands (`encode`, `probe`,
`profiles`, `batch`, `manifest`, `validate`), every `@Option`/`@Flag` each
one accepts, their real defaults and accepted values (verified against the
`ConverterEngine` enums they resolve to, not just the CLI's own `--help`
text — the two occasionally disagree, and the spec calls that out inline
where it matters), the JSON shapes the CLI reads and writes (`--json`
output, `--job-file`/`--ladder-file`/`--profile-file` input), and the POSIX
exit codes scripts can rely on.

This is the CLI you actually run:

```sh
meedya-convert encode --input movie.mov --profile "Web Standard" --output movie.mp4
```

The `paths` in this spec are a documentation convention, not a real HTTP
API — `servers` is set to `cli://meedya-convert` to make that explicit.
Each "path" is a subcommand, each "parameter" a flag.

### `meedya-http-api.yaml` — the HTTP server (experimental, #355)

Documents `APIServer` (`Sources/ConverterEngine/Server/APIServer.swift`), a
real `NWListener`-based HTTP server you can start from the macOS app's API
Server settings pane (there is no `meedya-convert serve` — the CLI cannot
start this server). **Most of its endpoints are fabricated stubs, not
working functionality**: `POST /encode` returns a canned "queued" response
without ever creating a job, `POST /probe` only checks whether a path
exists on disk, `GET /queue` always reports an empty queue, and
`GET /profiles` returns four hardcoded fake profiles unrelated to the
CLI/GUI's real 24 built-in profiles. This is tracked by reopened issue
**#355**. The spec marks every fabricated operation with `deprecated: true`,
an `x-status: not-implemented` extension, and a description that says so
in plain language — read those before building anything against this API.
`GET /status` and the bearer-token authentication are real, with two
caveats noted in the spec (`version` and `uptime` in the status payload are
hardcoded literals, not live values).

## Viewing the Swagger UI locally

The UI is a static HTML file with no build step. From this directory:

```sh
cd docs/api
python3 -m http.server 8000
```

Then open <http://localhost:8000/swagger-ui/>. Use the dropdown in the
Swagger UI top bar to switch between the CLI spec and the HTTP spec — a
banner above the operation list restates which one you're looking at and,
for the HTTP spec, links back to issue #355.

Any other static file server works too — `npx serve`, `php -S
localhost:8000`, VS Code's Live Server extension, etc. Opening
`swagger-ui/index.html` directly via `file://` also works in most browsers,
though some browsers block `fetch()` of local files under `file://` for
security reasons; if the spec dropdown shows a load error, serve the
directory over HTTP instead.

## Deploying to shared hosting

Because this is plain HTML/CSS/JS with no server-side code, it runs on any
static host — Apache, nginx, cPanel shared hosting, GitHub Pages, S3 +
CloudFront, etc.

1. Upload the entire `docs/api/` folder (all three items: the two `.yaml`
   files and the `swagger-ui/` folder) to your host, preserving that
   relative layout — `swagger-ui/index.html` loads the specs via relative
   paths (`../meedya-convert-api.yaml`, `../meedya-http-api.yaml`), so the
   two YAML files must stay one directory above `swagger-ui/`.
2. Point your browser at `swagger-ui/index.html` under wherever you
   uploaded it (e.g. `https://docs.example.com/meedyaconverter-api/swagger-ui/`).
3. No server configuration, rewrite rules, or MIME-type setup is required
   beyond what a default static host already provides — `.yaml` typically
   serves as `text/yaml` or `application/octet-stream`, either of which
   Swagger UI's `fetch()`-based YAML parser handles fine.

By default, `swagger-ui/index.html` loads the Swagger UI runtime
(`swagger-ui.css`, `swagger-ui-bundle.js`, `swagger-ui-standalone-preset.js`)
from the unpkg CDN, pinned to an exact `swagger-ui-dist` version so it
won't change under you. No Swagger UI binaries are vendored into this
repository. For offline or air-gapped hosting, download those same three
files and swap the `<link>`/`<script>` URLs in `swagger-ui/index.html` for
local paths — the full instructions (including the exact pinned version and
download commands) are in an HTML comment at the top of that file.
