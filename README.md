# Jena Fuseki docker image for DraCor

*This is an adaptation of the original Fuseki Dockerfile and scripts from
https://github.com/stain/jena-docker/.*

* Docker image: [dracor/fuseki](https://hub.docker.com/r/dracor/fuseki/)
* Base images:  [eclipse-temurin](https://hub.docker.com/r/_/eclipse-temurin/):25-jre
* Source: [Dockerfile](https://github.com/dracor-org/dracor-fuseki/blob/main/Dockerfile), [stain/jena-fuseki](https://github.com/stain/jena-docker/blob/master/jena-fuseki/Dockerfile), [Apache Jena Fuseki](https://jena.apache.org/download/)

This is a [Docker](https://www.docker.com/) image for running
[Apache Jena Fuseki](https://jena.apache.org/documentation/fuseki2/),
which is a [SPARQL 1.1](http://www.w3.org/TR/sparql11-overview/) server with a
web interface, backed by the
[Apache Jena TDB](https://jena.apache.org/documentation/tdb/) RDF triple store.

The image comes with the dataset `/dracor`, which is configured in
[config/dracor.ttl](config/dracor.ttl). Its default graph is the read-only
union of all named graphs, so data has to be written to named graphs.

The SPARQL query endpoints (`/dracor/sparql`, `/dracor/query`) and read-only
graph access (`/dracor/get`) are open to anyone. Everything that modifies data
(`/dracor/update`, `/dracor/data`, `/dracor/upload`) and the admin endpoints
(`/$/...`) require the `admin` user.

## License

Different licenses apply to files added by different Docker layers:

* dracor/fuseki [Dockerfile](https://github.com/dracor-org/dracor-fuseki/blob/main/Dockerfile): [Apache License, version 2.0](https://www.apache.org/licenses/LICENSE-2.0)
* Apache Jena (`/jena-fuseki` in the image): [Apache License, version 2.0](https://www.apache.org/licenses/LICENSE-2.0)
  See also: `docker run dracor/fuseki cat /jena-fuseki/NOTICE`
* OpenJDK (`/opt/java/openjdk/` in the image): [GPL 2.0 with Classpath exception](https://openjdk.java.net/legal/gplv2+ce.html)
  See `/opt/java/openjdk/legal/` in image
* Debian GNU/Linux (rest of `/`): [GPL 3](http://www.gnu.org/licenses/gpl-3.0) and [compatible licenses](https://www.debian.org/legal/licenses/), see `/usr/share/*/license` in image


## Usage

To build the image run:

    docker build -t dracor/fuseki .

To test an image (needs `curl` and `jq`; further arguments are passed to
`docker run`):

    test/smoke.sh dracor/fuseki
    test/smoke.sh dracor/fuseki --user 12345:0

To try out this image, try:

    docker run -p 3030:3030 dracor/fuseki

The Apache Jena Fuseki should then be available at http://localhost:3030/

To load RDF graphs, you will need to log in as the `admin` user. To see the
automatically generated admin password, see the output from above, or
use `docker logs` with the name of your container.

Note that the password is only generated on the first run, e.g. when the
volume `/fuseki` is an empty directory.

You can override the admin-password using the form
`-e ADMIN_PASSWORD=pw123`:

    docker run -p 3030:3030 -e ADMIN_PASSWORD=pw123 dracor/fuseki

To specify Java settings such as the amount of memory to allocate for the
heap (default: 4 GiB), set the `JVM_ARGS` environment with `-e`:

    docker run -p 3030:3030 -e JVM_ARGS=-Xmx2g dracor/fuseki

## Data persistence

Fuseki's data is stored in the Docker volume `/fuseki` within the container.
Note that unless you use `docker restart` or one of the mechanisms below, data
is lost between each run of the jena-fuseki image.

To store the data in a named Docker volume container `fuseki-data`
(recommended), create it first as:

    docker run --name fuseki-data -v /fuseki busybox

Then start fuseki using `--volumes-from`. This allows you to later upgrade the
jena-fuseki docker image without losing the data. The command below also uses
`-d` to start the container in the background.

    docker run -d --name fuseki -p 3030:3030 --volumes-from fuseki-data dracor/fuseki

If you want to store fuseki data in a specified location on the host (e.g. for
disk space or speed requirements), specify it using `-v`:

    docker run -d --name fuseki -p 3030:3030 -v /ssd/data/fuseki:/fuseki dracor/fuseki

Note that the `/fuseki` volume must only be accessed from a single Fuseki
container at a time.

### User ID

The container runs as the unprivileged user `fuseki` (UID 1001) in group 0.
It also runs under an arbitrary user ID in group 0, as used by OpenShift/OKD,
e.g. `docker run --user 12345:0 ...`. Everything in `/fuseki` is kept writable
for group 0.

A named or anonymous volume gets the right permissions automatically. A host
directory mounted with `-v` must be writable for UID 1001 or for group 0:

    sudo chown -R 1001:0 /ssd/data/fuseki && sudo chmod -R g=u /ssd/data/fuseki

To check the logs for the container you gave `--name fuseki`, use:

    docker logs fuseki

To stop the named container, use:

    docker stop fuseki

.. or press Ctrl-C.

To restart a named container (it will remember the volume and port config)

    docker restart fuseki

### TDB2 and compaction

The `/dracor` dataset uses [TDB2](https://jena.apache.org/documentation/tdb2/).
TDB2 keeps old data on disk when graphs are replaced or deleted, so the
database keeps growing until it is compacted:

    curl -u admin:$ADMIN_PASSWORD -X POST 'http://localhost:3030/$/compact/dracor?deleteOld=true'

## Upgrading Fuseki

If you want to upgrade the Fuseki container named `fuseki` which use the data
volume `fuseki-data` as recommended above, do:

    docker pull dracor/fuseki
    docker stop fuseki
    docker rm fuseki
    docker run -d --name fuseki -p 3030:3030 --volumes-from fuseki-data dracor/fuseki

### Upgrading from 1.x

Version 2 of this image updates Fuseki from 4.8 to 6.2, creates `/dracor` as
TDB2 with a union default graph, runs as an unprivileged user and requires the
`admin` user for all writes. It needs a new, empty `/fuseki` volume, into which
the data has to be loaded again. A 1.x volume cannot be reused:

* 1.x created `/dracor` as TDB1, while version 2 opens the same directory as
  TDB2. Fuseki starts without an error, but the dataset appears empty.
* The 1.x volume is owned by root and cannot be written by the unprivileged
  user.
* `shiro.ini` is only copied to `/fuseki` on the first start, so an old
  volume keeps the old access rules, which let anyone write to
  `/dracor/data`.

Writing to `/dracor` requires a version of
[dracor-api](https://github.com/dracor-org/dracor-api) that sends the admin
password (`FUSEKI_SECRET`) and writes each play to a named graph
([dracor-api#410](https://github.com/dracor-org/dracor-api/pull/410)).

## Customizing Fuseki configuration

If you need to modify Fuseki's configuration further, you can use the equivalent of:

    docker run --volumes-from fuseki-data -it ubuntu bash

and inspect `/fuseki` with the shell. Remember to restart fuseki afterwards:

    docker restart fuseki

The dataset configurations in `/fuseki/configuration` that come with the image
(`dracor.ttl`) are replaced on every start; other datasets added there are
kept. Do not expose SPARQL Update or the read-write graph store on the dataset
URL itself (as Fuseki's templates for new datasets do), as `shiro.ini` only
protects the `update`, `data` and `upload` endpoints.

### Additional JARs on Fuseki classpath

If you need to add additional JARs to the classpath, but do not want to
modify the volume `/fuseki`, then add the JARs to
`/fuseki-extra` which will be added as `/fuseki/extra` on start.
