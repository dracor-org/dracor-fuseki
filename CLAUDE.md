# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Docker image (`dracor/fuseki` on Docker Hub) that packages Apache Jena Fuseki
(SPARQL 1.1 server) for DraCor. It is an adaptation of
[stain/jena-docker](https://github.com/stain/jena-docker/) — there is no
application code, only `Dockerfile`, `entrypoint.sh` and `shiro.ini`. The
DraCor-specific difference is that the entrypoint creates an empty `/dracor`
dataset after Fuseki starts.

## Commands

```sh
docker build -t dracor/fuseki .
docker run -p 3030:3030 -e ADMIN_PASSWORD=pw123 dracor/fuseki   # UI at http://localhost:3030/
docker run -p 3030:3030 -e TDB=1 dracor/fuseki                  # use deprecated TDB1 instead of TDB2
docker run -p 3030:3030 -e JVM_ARGS=-Xmx2g dracor/fuseki        # override heap (default 4 GiB)
docker run -p 3030:3030 --user 12345:0 dracor/fuseki            # arbitrary UID in group 0 (OpenShift)
```

There are no tests or linters. The `docker build` itself is the smoke test: a
build step starts `fuseki-server` and curls `/$/ping`, failing the build if
Fuseki does not come up.

## How the pieces fit together

- **Dockerfile**: downloads the Fuseki tarball (ASF mirror, falling back to
  archive.apache.org), verifies it against `FUSEKI_SHA512`, installs to
  `FUSEKI_HOME=/jena-fuseki`. Config/data live in the volume
  `FUSEKI_BASE=/fuseki`. Runs under `tini` as UID 1001 in group 0; the image
  must also work under any UID in group 0, so everything Fuseki writes in
  `/fuseki` has to stay group-writable. `/jena-fuseki` is only read at
  runtime. The build-time ping test runs as root before `USER`.
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
  5. Starts the server in the background, polls `localhost:3030` until it
     returns 200, then POSTs to `/$/datasets` (basic auth as `admin`) to create
     `/dracor` with `dbType` `tdb2` (or `tdb` if `TDB=1`).
  6. Runs `chmod g=u` on its own files in `/fuseki`, because Fuseki creates
     `config.ttl` and `templates/*` with mode 600 regardless of the umask.
     Then `wait`s on the server.
- **shiro.ini**: auth template. `/$/status` and `/$/ping` are anonymous; all
  other `/$/**` admin endpoints, `/*/update/**` (SPARQL Update), `/*/data/**`
  (read-write Graph Store) and `/*/upload/**` require `admin`; everything else
  (SPARQL query, read-only `/*/get`) is anonymous. dracor-api, which writes
  to `/dracor/data` and `/dracor/update`, must send the admin password
  (its `FUSEKI_SECRET`).
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
