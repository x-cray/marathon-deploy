#!/bin/bash

set -e

ME=$(basename $0)

if [ $# -eq 0 ]; then
	echo "Usage: $ME <service-template-url> <environment> [instances-count]"
	exit 1
fi

function print_curl_result {
	BODY=$(echo "$3" | head -n-1 | jq '.')
	echo "$ME: Response code: $2, body: $BODY"
	echo "$ME: $1"
}

function curl_success_exit {
	# Display success message and exit.
	print_curl_result "$@"
	exit 0
}

function curl_error_exit {
	# Display error message and exit.
	print_curl_result "$@"
	exit 1
}

MASTER=$(mesos-resolve `cat /etc/mesos/zk` 2>/dev/null)
MARATHON=${MASTER%:*}:8080
SERVICE_TEMPLATE_S3=$1
SERVICE_TEMPLATE_FILE=$(basename "$SERVICE_TEMPLATE_S3")
ENVIRONMENT=$2
INSTANCES=${3:-1}

# Download service definition file.
echo "$ME: Downloading $SERVICE_TEMPLATE_S3"
curl -sSLO $SERVICE_TEMPLATE_S3

# Make necessary substitutions.
SERVICE_DEFINITION=$(sed "s/\$environment/$ENVIRONMENT/g;s/\$instances/$INSTANCES/g" $SERVICE_TEMPLATE_FILE)
APP_ID=$(jq -r '.id' <<< "$SERVICE_DEFINITION")
FORMATTED_SERVICE_DEFINITION=$(echo "$SERVICE_DEFINITION" | jq '.')

echo "$ME: Compiled service definition: $FORMATTED_SERVICE_DEFINITION"

# Try to create Marathon app definition.
echo "$ME: Trying to create new app $APP_ID"
CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST $MARATHON/v2/apps -d @- -H "Content-Type: application/json" <<< "$SERVICE_DEFINITION")
CREATE_CODE=$(tail -n1 <<< "$CREATE_RESPONSE")
if [ ${CREATE_CODE:0:1} -eq 2 ]; then
	curl_success_exit "Successfully created new app" "$CREATE_CODE" "$CREATE_RESPONSE"
elif [ $CREATE_CODE -eq 409 ]; then
	# Try to update Marathon app definition.
	print_curl_result "It seems that '$APP_ID' app already exists, trying to update its definition" "$CREATE_CODE" "$CREATE_RESPONSE"
	UPDATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT $MARATHON/v2/apps$APP_ID -d @- -H "Content-Type: application/json" <<< "$SERVICE_DEFINITION")
	UPDATE_CODE=$(tail -n1 <<< "$UPDATE_RESPONSE")
	if [ ${UPDATE_CODE:0:1} -eq 2 ]; then
		curl_success_exit "Successfully updated app" "$UPDATE_CODE" "$UPDATE_RESPONSE"
	else
		curl_error_exit "Error updating app" "$UPDATE_CODE" "$UPDATE_RESPONSE"
	fi;
else
	curl_error_exit "Error creating app" "$CREATE_CODE" "$CREATE_RESPONSE"
fi;
