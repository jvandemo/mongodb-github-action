#!/bin/sh

# Map input values from the GitHub Actions workflow to shell variables
MONGODB_VERSION=$1
MONGODB_REPLICA_SET=$2
MONGODB_PORT=$3
MONGODB_DB=$4
MONGODB_USERNAME=$5
MONGODB_PASSWORD=$6
MONGODB_DOCKER_CONTAINER_NAME=$7


if [ -z "$MONGODB_VERSION" ]; then
  echo ""
  echo "Missing MongoDB version in the [mongodb-version] input. Received value: $MONGODB_VERSION"
  echo ""

  exit 2
fi


if [ -z "$MONGODB_REPLICA_SET" ]; then
  echo "::group::Starting single-node instance, no replica set"
  echo "  - port [$MONGODB_PORT]"
  echo "  - version [$MONGODB_VERSION]"
  echo "  - database [$MONGODB_DB]"
  echo "  - credentials [$MONGODB_USERNAME:$MONGODB_PASSWORD]"
  echo "  - docker container name [$MONGODB_DOCKER_CONTAINER_NAME]"
  echo ""

  docker run --name $MONGODB_DOCKER_CONTAINER_NAME --publish $MONGODB_PORT:27017 -e MONGO_INITDB_DATABASE=$MONGODB_DB -e MONGO_INITDB_ROOT_USERNAME=$MONGODB_USERNAME -e MONGO_INITDB_ROOT_PASSWORD=$MONGODB_PASSWORD --detach mongo:$MONGODB_VERSION
  echo "::endgroup::"

  return
fi


echo "::group::Starting MongoDB as single-node replica set"
echo "  - port [$MONGODB_PORT]"
echo "  - version [$MONGODB_VERSION]"
echo "  - replica set [$MONGODB_REPLICA_SET]"
echo "  - docker container name [$MONGODB_DOCKER_CONTAINER_NAME]"
echo ""

docker run --name $MONGODB_DOCKER_CONTAINER_NAME --publish $MONGODB_PORT:$MONGODB_PORT --detach mongo:$MONGODB_VERSION --replSet $MONGODB_REPLICA_SET --port $MONGODB_PORT
echo "::endgroup::"


echo "::group::Waiting for MongoDB to accept connections"
sleep 1
TIMER=0

until docker exec --tty $MONGODB_DOCKER_CONTAINER_NAME mongo --port $MONGODB_PORT --eval "db.serverStatus()" # &> /dev/null
do
  sleep 1
  echo "."
  TIMER=$((TIMER + 1))

  if [[ $TIMER -eq 20 ]]; then
    echo "MongoDB did not initialize within 20 seconds. Exiting."
    exit 2
  fi
done
echo "::endgroup::"


echo "::group::Initiating replica set [$MONGODB_REPLICA_SET]"

docker exec --tty $MONGODB_DOCKER_CONTAINER_NAME mongo --port $MONGODB_PORT --eval "
  rs.initiate({
    \"_id\": \"$MONGODB_REPLICA_SET\",
    \"members\": [ {
       \"_id\": 0,
      \"host\": \"localhost:$MONGODB_PORT\"
    } ]
  })
"

echo "Success! Initiated replica set [$MONGODB_REPLICA_SET]"
echo "::endgroup::"


echo "::group::Checking replica set status [$MONGODB_REPLICA_SET]"
docker exec --tty $MONGODB_DOCKER_CONTAINER_NAME mongo --port $MONGODB_PORT --eval "
  rs.status()
"
echo "::endgroup::"
