#!/bin/bash

# push_into_slack_group.sh
#
# This script fetches the current on-call users for two PagerDuty schedules
# (primary and secondary) and updates a Slack user group with these users.
#
# Requirements:
# - jq: Command-line JSON processor
# - curl: Command-line tool for transferring data with URLs
#
# Environment Variables:
# - PAGER_TOKEN: PagerDuty API token (with read access)
# - SLACK_TOKEN: Slack API token (with usergroups:write and users:read scope)

set -euo pipefail

# --- Configuration & Validation ---

PAGER_TOKEN="${PAGER_TOKEN:-}"
SLACK_TOKEN="${SLACK_TOKEN:-}"

if [[ -z "$PAGER_TOKEN" ]]; then
    echo "Error: PAGER_TOKEN environment variable is not set." >&2
    exit 1
fi

if [[ -z "$SLACK_TOKEN" ]]; then
    echo "Error: SLACK_TOKEN environment variable is not set." >&2
    exit 1
fi

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <PRIMARY_SCHEDULE_ID> <SECONDARY_SCHEDULE_ID> <SLACK_GROUP_HANDLE_OR_NAME>" >&2
    echo "Example: $0 PXXXXXX PYYYYYY 'team-oncall'" >&2
    exit 1
fi

PRIMARY_SCHEDULE_ID="$1"
SECONDARY_SCHEDULE_ID="$2"
SLACK_TARGET="$3"

# Escalation levels (as defined in the original script)
ESCALATION_LEVEL_PRIMARY=1
ESCALATION_LEVEL_SECONDARY=2

PAGER_API_BASE="https://api.pagerduty.com"
SLACK_API_BASE="https://slack.com/api"

# --- Functions ---

log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*" >&2
}

get_oncall_user_email() {
    local schedule_id="$1"
    local escalation_level="$2"

    log "Fetching on-call user for schedule ${schedule_id} (level ${escalation_level})..."

    # Get the user self-link from oncalls
    local user_url
    user_url=$(curl -s -G -H "Authorization: Token token=${PAGER_TOKEN}" \
        -H "Accept: application/vnd.pagerduty+json;version=2" \
        --data-urlencode "time_zone=UTC" \
        --data-urlencode "schedule_ids[]=${schedule_id}" \
        "${PAGER_API_BASE}/oncalls" | \
        jq -r ".oncalls[] | select(.escalation_level == ${escalation_level}) | .user.self // empty" | head -n 1)

    if [[ -z "$user_url" ]]; then
        log "Error: No on-call user found for schedule ${schedule_id} at escalation level ${escalation_level}."
        return 1
    fi

    # Get the user email
    local email
    email=$(curl -s -H "Authorization: Token token=${PAGER_TOKEN}" \
        -H "Accept: application/vnd.pagerduty+json;version=2" \
        "${user_url}" | jq -r '.user.email // empty')

    if [[ -z "$email" ]]; then
        log "Error: Could not retrieve email for user at ${user_url}."
        return 1
    fi

    echo "$email"
}

get_slack_user_id() {
    local email="$1"
    log "Looking up Slack user ID for email: ${email}..."

    local user_id
    user_id=$(curl -s -H "Authorization: Bearer ${SLACK_TOKEN}" \
        -G --data-urlencode "email=${email}" \
        "${SLACK_API_BASE}/users.lookupByEmail" | jq -r '.user.id // empty')

    if [[ -z "$user_id" ]]; then
        log "Error: Slack user not found for email ${email}."
        return 1
    fi
    echo "$user_id"
}

get_slack_group_id() {
    local target="$1"
    log "Finding Slack user group ID for: ${target}..."

    local group_id
    group_id=$(curl -s -H "Authorization: Bearer ${SLACK_TOKEN}" \
        "${SLACK_API_BASE}/usergroups.list" | \
        jq -r --arg target "$target" '.usergroups[] | select(.handle == $target or .name == $target) | .id' | head -n 1)

    if [[ -z "$group_id" ]]; then
        # Try a partial match if exact match fails (to maintain backward compatibility with 'contains')
        group_id=$(curl -s -H "Authorization: Bearer ${SLACK_TOKEN}" \
            "${SLACK_API_BASE}/usergroups.list" | \
            jq -r --arg target "$target" '.usergroups[] | select(.name | contains($target)) | .id' | head -n 1)
    fi

    if [[ -z "$group_id" ]]; then
        log "Error: Could not find Slack user group with handle or name matching '${target}'."
        return 1
    fi
    echo "$group_id"
}

# --- Main ---

# 1. Get Emails from PagerDuty
PRIMARY_EMAIL=$(get_oncall_user_email "$PRIMARY_SCHEDULE_ID" "$ESCALATION_LEVEL_PRIMARY")
SECONDARY_EMAIL=$(get_oncall_user_email "$SECONDARY_SCHEDULE_ID" "$ESCALATION_LEVEL_SECONDARY")

# 2. Get Slack IDs
PRIMARY_SLACK_ID=$(get_slack_user_id "$PRIMARY_EMAIL")
SECONDARY_SLACK_ID=$(get_slack_user_id "$SECONDARY_EMAIL")

# 3. Get Slack Group ID
USERGROUP_ID=$(get_slack_group_id "$SLACK_TARGET")

# 4. Update Slack Group
log "Updating Slack group ${SLACK_TARGET} (${USERGROUP_ID}) with members: ${PRIMARY_SLACK_ID}, ${SECONDARY_SLACK_ID}..."

UPDATE_RESULT=$(curl -s -X POST -H "Authorization: Bearer ${SLACK_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "{\"usergroup\": \"${USERGROUP_ID}\", \"users\": \"${PRIMARY_SLACK_ID},${SECONDARY_SLACK_ID}\"}" \
    "${SLACK_API_BASE}/usergroups.users.update")

if [[ $(echo "$UPDATE_RESULT" | jq -r '.ok') == "true" ]]; then
    log "Success! Slack group updated."
else
    ERROR_MSG=$(echo "$UPDATE_RESULT" | jq -r '.error')
    log "Error: Failed to update Slack group. API responded with: ${ERROR_MSG}"
    exit 1
fi
