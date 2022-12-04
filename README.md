# Jena Fuseki docker image for DraCor

<!--
* Docker image: [dracor/fuseki](https://hub.docker.com/r/dracor/fuseki/)
* Base images:  [openjdk](https://hub.docker.com/r/_/openjdk/):11-jre-slim-buster
* Source: [Dockerfile](https://github.com/dracor-org/dracor-fuseki/blob/master/Dockerfile), [Apache Jena Fuseki](https://jena.apache.org/download/)
-->

This is an adaptation of the original Fuseki Dockerfile and scripts from
https://github.com/stain/jena-docker/.

This is a [Docker](https://www.docker.com/) image for running
[Apache Jena Fuseki](https://jena.apache.org/documentation/fuseki2/),
which is a [SPARQL 1.1](http://www.w3.org/TR/sparql11-overview/) server with a
web interface, backed by the
[Apache Jena TDB](https://jena.apache.org/documentation/tdb/) RDF triple store.

## License

Different licenses apply to files added by different Docker layers:

* dracor/fuseki [Dockerfile](https://github.com/dracor-org/dracor-fuseki/blob/master/jena-fuseki/Dockerfile): [Apache License, version 2.0](https://www.apache.org/licenses/LICENSE-2.0)
* Apache Jena (`/jena-fuseki` in the image): [Apache License, version 2.0](https://www.apache.org/licenses/LICENSE-2.0)
  See also: `docker run dracor/fuseki cat /jena-fuseki/NOTICE`
* OpenJDK (`/usr/local/openjdk-11/` in the image): [GPL 2.0 with Classpath exception](https://openjdk.java.net/legal/gplv2+ce.html)
  See `/usr/local/openjdk-11/legal/` in image
* Debian GNU/Linux (rest of `/`): [GPL 3](http://www.gnu.org/licenses/gpl-3.0) and [compatible licenses](https://www.debian.org/legal/licenses/), see `/usr/share/*/license` in image


## Usage

To build the image run:

    docker build -t dracor/fuseki .

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
heap (default: 1200 MiB), set the `JVM_ARGS` environment with `-e`:

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

To check the logs for the container you gave `--name fuseki`, use:

    docker logs fuseki

To stop the named container, use:

    docker stop fuseki

.. or press Ctrl-C.

To restart a named container (it will remember the volume and port config)

    docker restart fuseki

### Using TDB 2

To use [TDB v2](https://jena.apache.org/documentation/tdb2/) you can pass the environment variable with `-e TDB=2`

     docker run -p 3030:3030 -e TDB=2 dracor/fuseki

## Upgrading Fuseki

If you want to upgrade the Fuseki container named `fuseki` which use the data
volume `fuseki-data` as recommended above, do:

    docker pull dracor/fuseki
    docker stop fuseki
    docker rm fuseki
    docker run -d --name fuseki -p 3030:3030 --volumes-from fuseki-data dracor/fuseki

## Create empty datasets

You can create empty datasets at startup with:

    docker run -d --name fuseki -p 3030:3030 -e FUSEKI_DATASET_1=mydataset -e FUSEKI_DATASET_2=otherdataset dracor/fuseki

This will create 2 empty datasets: mydataset and otherdataset.

## Customizing Fuseki configuration

If you need to modify Fuseki's configuration further, you can use the equivalent of:

    docker run --volumes-from fuseki-data -it ubuntu bash

and inspect `/fuseki` with the shell. Remember to restart fuseki afterwards:

    docker restart fuseki

### Additional JARs on Fuseki classpath

If you need to add additional JARs to the classpath, but do not want to
modify the volume `/fuseki`, then add the JARs to
`/fuseki-extra` which will be added as `/fuseki/extra` on start.

