#!/bin/bash

SCHEDULE_ID_PRIMARY=$1 # PRIMARY Oncall schedule on pagerduty 
SCHEDULE_ID_SECONDARY=$2 # SECONDARY Oncall schedule on pagerduty 
ESCALATION_POLICY_PRIMARY=1
ESCALATION_POLICY_SECONDARY=2
NAME=$3 # Handle that @ on slack

#USER PRIMARY INFO
USER_URL_PRIMARY=$(curl -s -G -H "Authorization: Token token=${PAGER_TOKEN}" \
  -H "Accept: application/vnd.pagerduty+json;version=2" \
  --data-urlencode "time_zone=UTC" \
  --data-urlencode "schedule_ids[]=${SCHEDULE_ID_PRIMARY}" \
  "https://api.pagerduty.com/oncalls" \
  | jq ".oncalls | .[] | select(.escalation_level | contains(${ESCALATION_POLICY_PRIMARY})).user.self" | tr -d '"')

USER_EMAIL_PRIMARY=$(curl -s -G -H "Authorization: Token token=${PAGER_TOKEN}" \
  -H "Accept: application/vnd.pagerduty+json;version=2" \
  "${USER_URL_PRIMARY}" \
  | jq ".user.email" | tr -d '"')


USER_ID_PRIMARY=$(curl -s -X GET \
  "https://slack.com/api/users.lookupByEmail?token=${SLACK_TOKEN}&email=${USER_EMAIL_PRIMARY}" \
  | jq '.user.id' | tr -d '"')

USERGROUP_ID=$(curl -s -X GET \
  "https://slack.com/api/usergroups.list?token=${SLACK_TOKEN}" \
  | jq ".usergroups | .[] | select(.name | contains (\"${NAME}\")).id" | tr -d '"' | tr -d ' ')

echo "User primary: "
echo $USER_URL_PRIMARY
echo $USER_EMAIL_PRIMARY
echo $USERGROUP_ID
echo $USER_ID_PRIMARY

#USER SECONDARY INFO
USER_URL_SECONDARY=$(curl -s -G -H "Authorization: Token token=${PAGER_TOKEN}" \
  -H "Accept: application/vnd.pagerduty+json;version=2" \
  --data-urlencode "time_zone=UTC" \
  --data-urlencode "schedule_ids[]=${SCHEDULE_ID_SECONDARY}" \
  "https://api.pagerduty.com/oncalls" \
  | jq ".oncalls | .[] | select(.escalation_level | contains(${ESCALATION_POLICY_SECONDARY})).user.self" | tr -d '"')

USER_EMAIL_SECONDARY=$(curl -s -G -H "Authorization: Token token=${PAGER_TOKEN}" \
  -H "Accept: application/vnd.pagerduty+json;version=2" \
  "${USER_URL_SECONDARY}" \
  | jq ".user.email" | tr -d '"')


USER_ID_SECONDARY=$(curl -s -X GET \
  "https://slack.com/api/users.lookupByEmail?token=${SLACK_TOKEN}&email=${USER_EMAIL_SECONDARY}" \
  | jq '.user.id' | tr -d '"')

echo "User secondary: "
echo $USER_URL_SECONDARY
echo $USER_EMAIL_SECONDARY
echo $USERGROUP_ID
echo $USER_ID_SECONDARY

curl -s -X POST "https://slack.com/api/usergroups.users.update?token=${SLACK_TOKEN}&usergroup=${USERGROUP_ID}&users=${USER_ID_PRIMARY},${USER_ID_SECONDARY}" 