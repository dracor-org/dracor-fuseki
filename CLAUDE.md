# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Docker image (`dracor/fuseki` on Docker Hub) that packages Apache Jena Fuseki
(SPARQL 1.1 server) for DraCor. It is an adaptation of
[stain/jena-docker](https://github.com/stain/jena-docker/) — there is no
application code, only `Dockerfile`, `entrypoint.sh`, `shiro.ini` and the
dataset configuration in `config/`. The DraCor-specific difference is the
`/dracor` dataset defined in `config/dracor.ttl`.

## Commands

```sh
docker build -t dracor/fuseki .
docker run -p 3030:3030 -e ADMIN_PASSWORD=pw123 dracor/fuseki   # UI at http://localhost:3030/
docker run -p 3030:3030 -e JVM_ARGS=-Xmx2g dracor/fuseki        # override heap (default 4 GiB)
docker run -p 3030:3030 --user 12345:0 dracor/fuseki            # arbitrary UID in group 0 (OpenShift)
```

There are no tests or linters. The `docker build` itself is the smoke test: a
build step starts `fuseki-server` with the datasets from `config/` and curls
`/$/ping` and `/dracor/query`, failing the build if Fuseki does not come up or
skips `/dracor`. Fuseki 6 exits on a configuration file with a Turtle syntax
error, but only logs an assembler error (e.g. a dangling reference) and starts
without that dataset, which `/$/ping` does not notice.

## How the pieces fit together

- **Dockerfile**: downloads the Fuseki tarball (ASF mirror, falling back to
  archive.apache.org), verifies it against `FUSEKI_SHA512`, installs to
  `FUSEKI_HOME=/jena-fuseki`. Config/data live in the volume
  `FUSEKI_BASE=/fuseki`. Runs under `tini` as UID 1001 in group 0; the image
  must also work under any UID in group 0, so everything Fuseki writes in
  `/fuseki` has to stay group-writable. `/jena-fuseki` is only read at
  runtime. The build-time test runs as root before `USER` and removes `/fuseki`
  again, as the datasets' TDB2 locations are absolute paths in `/fuseki`.
- **Fuseki 6** starts the "main" server with UI (`FusekiServerUICmd`); there is
  no webapp/WAR anymore. Its stricter IRI parser rejects some IRIs Fuseki 4
  accepted (e.g. `urn:g`).
- **Upgrading Fuseki**: change `FUSEKI_VERSION` *and* `FUSEKI_SHA512` together
  (checksum from the `.tar.gz.sha512` on https://jena.apache.org/download/),
  otherwise the build fails at `sha512sum -c`.
- **entrypoint.sh** (runs on every container start):
  1. Sets `umask 0002`.
  2. First run only (no `/fuseki/shiro.ini`): copies the template `shiro.ini`
     into `/fuseki` and, if `ADMIN_PASSWORD` is unset, generates one with
     `pwgen` and prints it to the log.
  3. If `ADMIN_PASSWORD` is set, `envsubst` replaces the `${ADMIN_PASSWORD}`
     placeholder in `/fuseki/shiro.ini`. Once substituted, the placeholder is
     gone, so later password changes via env have no effect on an existing
     volume. Likewise, changes to the repo's `shiro.ini` never reach an
     existing volume.
  4. Symlinks `/fuseki-extra` to `/fuseki/extra` (extra JARs on the classpath).
  5. Copies `/jena-fuseki/configuration/*.ttl` (the repo's `config/`) to
     `/fuseki/configuration`, overwriting older versions, so that changes to
     them, unlike `shiro.ini`, reach an existing volume.
  6. Starts the server in the background and polls `localhost:3030` until it
     returns 200; exits with 1 if the server dies meanwhile, or if `/dracor`
     is not available then (Fuseki skipped its configuration).
  7. Runs `chmod g=u` on its own files in `/fuseki`, because Fuseki creates
     `config.ttl` and `templates/*` with mode 600 regardless of the umask.
     Then `wait`s on the server.
- **shiro.ini**: auth template. `/$/status` and `/$/ping` are anonymous; all
  other `/$/**` admin endpoints, `/*/update/**` (SPARQL Update), `/*/data/**`
  (read-write Graph Store) and `/*/upload/**` require `admin`; everything else
  (SPARQL query, read-only `/*/get`) is anonymous. dracor-api, which writes
  to `/dracor/data` and `/dracor/update`, must send the admin password
  (its `FUSEKI_SECRET`).
- **config/*.ttl**: Fuseki assembler files, one per dataset. Writing
  operations must only be exposed on the endpoints `update`, `data` and
  `upload`, never on the dataset URL itself (`fuseki:endpoint` without
  `fuseki:name`): `shiro.ini` cannot tell queries from updates there. Fuseki's
  own templates (used when creating a dataset via `/$/datasets`) do expose
  them, so a dataset created that way is writable anonymously.
- **/dracor** is TDB2 with `tdb2:unionDefaultGraph true`: the default graph is
  the read-only union of all named graphs. Writes without a graph succeed but
  land in the hidden real default graph (`<urn:x-arq:DefaultGraph>`).
- **TDB2** grows with every replaced graph until compacted
  (`POST /$/compact/dracor?deleteOld=true`).

## Release / CI

- `.github/workflows/docker-publish.yml` builds multi-arch (`linux/amd64`,
  `linux/arm64`) and pushes to Docker Hub. It runs on a **published GitHub
  release** (or manual dispatch); image tags come from the release's semver
  tag (`X.Y.Z` and `X.Y`). Pushing to `main` does not publish.
- Actions are pinned to commit SHAs with a version comment; Dependabot updates
  GitHub Actions monthly in grouped PRs. It ignores major versions of the
  `eclipse-temurin` base image: its major version is the Java version, which
  is moved by hand from LTS to LTS (25 now, next 29).
