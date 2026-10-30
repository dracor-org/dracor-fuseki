#!/bin/bash
#
# Smoke test for the dracor/fuseki image
#
# Starts a container from the image with a fresh volume and checks access
# control, the union default graph, the requests dracor-api sends, and that
# the data survives a restart. Further arguments are passed to `docker run`.
#
# Usage: test/smoke.sh IMAGE [DOCKER_RUN_OPTION...]
# Example: test/smoke.sh dracor/fuseki --user 12345:0

set -euo pipefail

if [ $# -lt 1 ] ; then
  echo "Usage: $0 IMAGE [DOCKER_RUN_OPTION...]" >&2
  exit 2
fi
IMAGE=$1
shift

PW=smoke-test
NAME=fuseki-smoke-$$
VOLUME=fuseki-smoke-$$
FAILED=0

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker volume rm "$VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_up() {
  for _ in $(seq 1 120) ; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" != true ] ; then
      echo "Container exited:" >&2
      docker logs "$NAME" >&2
      exit 1
    fi
    if curl -s --fail -o /dev/null "$BASE/query?query=ASK%7B%7D" ; then
      return
    fi
    sleep 1
  done
  echo "Fuseki did not come up:" >&2
  docker logs "$NAME" >&2
  exit 1
}

# check DESCRIPTION EXPECTED_STATUS_REGEX CURL_ARG...
check() {
  local desc=$1 expected=$2 status
  shift 2
  status=$(curl -s -o /dev/null -w '%{http_code}' "$@" || true)
  if [[ $status =~ ^($expected)$ ]] ; then
    echo "ok   $desc ($status)"
  else
    echo "FAIL $desc: got $status, expected $expected"
    FAILED=1
  fi
}

# check_value DESCRIPTION EXPECTED ACTUAL
check_value() {
  if [ "$2" = "$3" ] ; then
    echo "ok   $1 ($3)"
  else
    echo "FAIL $1: got '$3', expected '$2'"
    FAILED=1
  fi
}

# Result of a SPARQL query returning a single value
select_value() {
  curl -s --fail "$BASE/query" --data-urlencode "query=$1" \
    -H 'Accept: text/csv' | tail -n +2 | tr -d '\r'
}

graph_url() {
  echo "$BASE/data?graph=$(printf '%s' "$1" | jq -sRr @uri)"
}

# RDF/XML for a play, as dracor-api sends it
play_rdf() {
  cat <<EOF
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#">
  <rdf:Description rdf:about="http://dracor.org/id/$1">
    <rdfs:label>$1</rdfs:label>
  </rdf:Description>
</rdf:RDF>
EOF
}

UPDATE=(-H 'Content-Type: application/sparql-update')
ADMIN=(-u "admin:$PW")
COUNT_ALL='SELECT (COUNT(*) AS ?n) { ?s ?p ?o }'
COUNT_NAMED='SELECT (COUNT(*) AS ?n) { GRAPH ?g { ?s ?p ?o } }'

docker run -d --name "$NAME" -v "$VOLUME:/fuseki" -p 127.0.0.1::3030 \
  -e ADMIN_PASSWORD="$PW" "$@" "$IMAGE" >/dev/null
BASE="http://$(docker port "$NAME" 3030/tcp | head -n 1)/dracor"
wait_up

echo "# Anonymous access"
check "query via GET /dracor/sparql" 200 \
  "$BASE/sparql?query=ASK%7B%7D"
check "query via POST /dracor" 200 \
  -X POST "$BASE" --data-urlencode 'query=ASK {}'
check "update via POST /dracor is refused" '4..' \
  -X POST "$BASE" "${UPDATE[@]}" \
  --data 'INSERT DATA { GRAPH <http://ex/g> { <http://ex/s> <http://ex/p> "anon" } }'
check "PUT /dracor?graph is refused" '4..' \
  -X PUT "$BASE?graph=http%3A%2F%2Fex%2Fg" -H 'Content-Type: text/turtle' \
  --data '<http://ex/s> <http://ex/p> "anon" .'
check "DELETE /dracor?default is refused" '4..' -X DELETE "$BASE?default"
check "POST /dracor/update needs auth" 401 \
  -X POST "$BASE/update" "${UPDATE[@]}" \
  --data 'INSERT DATA { GRAPH <http://ex/g> { <http://ex/s> <http://ex/p> "anon" } }'
check "PUT /dracor/data needs auth" 401 \
  -X PUT "$(graph_url http://ex/g)" -H 'Content-Type: text/turtle' \
  --data '<http://ex/s> <http://ex/p> "anon" .'
check "POST /dracor/upload needs auth" 401 \
  -X POST "$BASE/upload" -F 'file=@/dev/null;filename=x.ttl'
check "GET /$/datasets needs auth" 401 "${BASE%/dracor}/\$/datasets"
check_value "no anonymous writes went through" 0 "$(select_value "$COUNT_ALL")"

echo "# Writes as dracor-api does them"
for play in ger/a ger/b rus/c ; do
  check "admin PUT graph of $play" '20.' "${ADMIN[@]}" \
    -X PUT "$(graph_url "http://dracor.org/$play")" \
    -H 'Content-Type: application/rdf+xml' --data "$(play_rdf "${play#*/}")"
done
check "admin update into a named graph" '20.' "${ADMIN[@]}" \
  -X POST "$BASE/update" "${UPDATE[@]}" \
  --data 'INSERT DATA { GRAPH <http://dracor.org/rus/c> { <http://dracor.org/id/c> <http://ex/p> "x" } }'
check_value "named graphs hold all triples" 4 "$(select_value "$COUNT_NAMED")"
check_value "default graph is their union" 4 "$(select_value "$COUNT_ALL")"
check "anonymous GET /dracor/get?graph" 200 \
  "$BASE/get?graph=http%3A%2F%2Fdracor.org%2Fger%2Fa"
check "admin DELETE graph of ger/b" '20.' "${ADMIN[@]}" \
  -X DELETE "$(graph_url http://dracor.org/ger/b)"
check "admin DELETE missing graph" 404 "${ADMIN[@]}" \
  -X DELETE "$(graph_url http://dracor.org/ger/zzz)"
check "admin update dropping corpus ger" '20.' "${ADMIN[@]}" \
  -X POST "$BASE/update" "${UPDATE[@]}" \
  --data "DELETE { GRAPH ?g { ?s ?p ?o } } WHERE { GRAPH ?g { ?s ?p ?o } FILTER(STRSTARTS(STR(?g), 'http://dracor.org/ger/')) }"
check_value "only rus/c is left" "http://dracor.org/rus/c" \
  "$(select_value 'SELECT DISTINCT ?g { GRAPH ?g { ?s ?p ?o } }')"

echo "# Restart"
docker restart "$NAME" >/dev/null
BASE="http://$(docker port "$NAME" 3030/tcp | head -n 1)/dracor"
wait_up
check_value "data survives a restart" 2 "$(select_value "$COUNT_ALL")"

if [ "$FAILED" != 0 ] ; then
  echo "Smoke test failed, container log:"
  docker logs "$NAME"
  exit 1
fi
echo "All checks passed"
