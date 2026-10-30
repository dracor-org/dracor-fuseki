# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Use an LTS release of Java (Fuseki 6 needs at least Java 21)
FROM eclipse-temurin:25-jre

ENV LANG C.UTF-8
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
       bash curl ca-certificates findutils coreutils gettext pwgen procps tini; \
    rm -rf /var/lib/apt/lists/*

# Update below according to https://jena.apache.org/download/
# and checksum for apache-jena-fuseki-6.x.x.tar.gz.sha512
ENV FUSEKI_SHA512 ba65f5867d2d4741b2ed9e2af5a0d4fbb447909894ab2a0c6bc4dac8997f4fe339c87b13c48d45d054977769f0f8bf763ea346b1f7792d5cdc458041bd43a132
ENV FUSEKI_VERSION 6.2.0
ENV ASF_MIRROR https://www.apache.org/dyn/mirrors/mirrors.cgi?action=download&filename=
ENV ASF_ARCHIVE https://archive.apache.org/dist/

LABEL org.opencontainers.image.url https://github.com/dracor-org/dracor-fuseki/tree/master/
LABEL org.opencontainers.image.source https://github.com/dracor-org/dracor-fuseki/
LABEL org.opencontainers.image.documentation https://jena.apache.org/documentation/fuseki2/
LABEL org.opencontainers.image.title "Apache Jena Fuseki"
LABEL org.opencontainers.image.description "Fuseki is a SPARQL 1.1 server with a web interface, backed by the Apache Jena TDB RDF triple store."
LABEL org.opencontainers.image.version ${FUSEKI_VERSION}
LABEL org.opencontainers.image.licenses "(Apache-2.0 AND (GPL-2.0 WITH Classpath-exception-2.0) AND GPL-3.0)"
LABEL org.opencontainers.image.authors "Apache Jena Fuseki by https://jena.apache.org/; this image by https://orcid.org/0000-0001-9842-9718"

# Config and data
ENV FUSEKI_BASE /fuseki

# Installation folder
ENV FUSEKI_HOME /jena-fuseki

WORKDIR /tmp
# published sha512 checksum
RUN echo "$FUSEKI_SHA512  fuseki.tar.gz" > fuseki.tar.gz.sha512
# Download/check/unpack/move in one go (to reduce image size)
RUN     (curl --location --silent --show-error --fail --retry-connrefused --retry 3 --output fuseki.tar.gz ${ASF_MIRROR}jena/binaries/apache-jena-fuseki-$FUSEKI_VERSION.tar.gz || \
         curl --fail --silent --show-error --retry-connrefused --retry 3 --output fuseki.tar.gz $ASF_ARCHIVE/jena/binaries/apache-jena-fuseki-$FUSEKI_VERSION.tar.gz) && \
        sha512sum -c fuseki.tar.gz.sha512 && \
        tar zxf fuseki.tar.gz && \
        mv apache-jena-fuseki* $FUSEKI_HOME && \
        rm fuseki.tar.gz* && \
        cd $FUSEKI_HOME && chmod 755 fuseki-server

# As "localhost" is often inaccessible within Docker container,
# we'll enable basic-auth with a random admin password
# (which we'll generate on start-up)
COPY shiro.ini $FUSEKI_HOME/shiro.ini
# Dataset configurations, copied to $FUSEKI_BASE/configuration on start
COPY config/ $FUSEKI_HOME/configuration/
COPY entrypoint.sh /
RUN chmod 755 /entrypoint.sh

# Test the install and the dataset configurations: Fuseki skips a dataset
# whose configuration it cannot build, but still answers the ping. 20s sleep
# because Docker Hub. The databases are created in $FUSEKI_BASE, so remove it
# in the same layer.
RUN mkdir -p $FUSEKI_BASE/configuration && \
    cp $FUSEKI_HOME/configuration/*.ttl $FUSEKI_BASE/configuration/ && \
    { $FUSEKI_HOME/fuseki-server & } && \
    sleep 20 && \
    curl -sS --fail 'http://localhost:3030/$/ping' && \
    curl -sS --fail -o /dev/null 'http://localhost:3030/dracor/query?query=ASK%7B%7D' && \
    kill $! && { wait $! || true; } && \
    rm -rf $FUSEKI_BASE

WORKDIR $FUSEKI_HOME

# fuseki is in group 0 (root group), so that an arbitrary user ID in group 0,
# as used by OpenShift/OKD, has the same rights as fuseki
RUN useradd --uid 1001 --gid 0 --no-create-home --home-dir $FUSEKI_BASE fuseki

# Make sure we start with empty /fuseki, writable for the fuseki user and
# group 0, so that the image also runs under an arbitrary user ID in group 0
RUN rm -rf $FUSEKI_BASE && \
    mkdir $FUSEKI_BASE && \
    chown 1001:0 $FUSEKI_BASE && \
    chmod 775 $FUSEKI_BASE
VOLUME $FUSEKI_BASE

USER 1001:0

EXPOSE 3030
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["/jena-fuseki/fuseki-server"]
