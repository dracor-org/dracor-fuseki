#!/bin/bash
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

set -e

# keep files created in $FUSEKI_BASE writable for group 0, so that the volume
# also works under another user ID in group 0
umask 0002

if [ ! -f "$FUSEKI_BASE/shiro.ini" ] ; then
  # First time
  echo "###################################"
  echo "Initializing Apache Jena Fuseki"
  echo ""
  cp "$FUSEKI_HOME/shiro.ini" "$FUSEKI_BASE/shiro.ini"
  if [ -z "$ADMIN_PASSWORD" ] ; then
    ADMIN_PASSWORD=$(pwgen -s 15)
    echo "Randomly generated admin password:"
    echo ""
    echo "admin=$ADMIN_PASSWORD"
  fi
  echo ""
  echo "###################################"
fi

if [ -d "/fuseki-extra" ] && [ ! -d "$FUSEKI_BASE/extra" ] ; then
  ln -s "/fuseki-extra" "$FUSEKI_BASE/extra"
fi

# $ADMIN_PASSWORD only modifies if ${ADMIN_PASSWORD}
# is in shiro.ini
if [ -n "$ADMIN_PASSWORD" ] ; then
  export ADMIN_PASSWORD
  envsubst '${ADMIN_PASSWORD}' < "$FUSEKI_BASE/shiro.ini" > "$FUSEKI_BASE/shiro.ini.$$" && \
    mv "$FUSEKI_BASE/shiro.ini.$$" "$FUSEKI_BASE/shiro.ini"
fi

# Install the dataset configurations of the image on every start, so that
# changes to them also reach an existing volume
mkdir -p "$FUSEKI_BASE/configuration"
cp "$FUSEKI_HOME"/configuration/*.ttl "$FUSEKI_BASE/configuration/"

# fork
exec "$@" &
FUSEKI_PID=$!

# Wait until server is up; Fuseki exits on a configuration it cannot parse
while [[ $(curl -I http://localhost:3030 2>/dev/null | head -n 1 | cut -d$' ' -f2) != '200' ]]; do
  if ! kill -0 "$FUSEKI_PID" 2>/dev/null ; then
    echo "ERROR: Fuseki exited during startup" >&2
    exit 1
  fi
  sleep 1s
done

# Fuseki skips a dataset whose configuration it cannot build and runs without
# it; DraCor is of no use without /dracor, so stop instead
if ! curl -s --fail -o /dev/null 'http://localhost:3030/dracor/query?query=ASK%7B%7D' ; then
  echo "ERROR: dataset /dracor is not available, see the Fuseki log above" >&2
  kill "$FUSEKI_PID"
  exit 1
fi

# Fuseki creates config.ttl and templates/* readable for their owner only;
# give group 0 the same rights, so that the volume also works under another
# user ID in group 0
find "$FUSEKI_BASE" -user "$(id -u)" ! -type l -exec chmod g=u {} + || true

# rejoin our exec
wait
