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

# --- Version ---
VERSION="2.0.0"

# --- Default Configuration ---
CACHE_DIR="${CACHE_DIR:-/tmp/pd2slack-cache}"
CACHE_TTL="${CACHE_TTL:-300}"  # 5 minutes default
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-1}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
DEBUG="${DEBUG:-false}"
QUIET="${QUIET:-false}"
JSON_OUTPUT="${JSON_OUTPUT:-false}"
LOG_FILE="${LOG_FILE:-}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-false}"
HEALTH_CHECK="${HEALTH_CHECK:-false}"
CONFIG_FILE="${CONFIG_FILE:-}"
API_TIMEOUT="${API_TIMEOUT:-30}"

# --- Configuration & Validation ---
PAGER_TOKEN="${PAGER_TOKEN:-}"
SLACK_TOKEN="${SLACK_TOKEN:-}"

ESCALATION_LEVEL_PRIMARY=1
ESCALATION_LEVEL_SECONDARY=2

PAGER_API_BASE="https://api.pagerduty.com"
SLACK_API_BASE="https://slack.com/api"

# Exit codes
EXIT_SUCCESS=0
EXIT_CONFIG_ERROR=1
EXIT_API_ERROR=2
EXIT_PARTIAL_FAILURE=3

# --- Functions ---

log() {
    if [[ "$QUIET" == "true" ]]; then
        return
    fi
    
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date +'%Y-%m-%dT%H:%M:%S%z')"
    
    # Check verbosity
    if [[ "$level" == "DEBUG" ]] && [[ "$DEBUG" != "true" ]]; then
        return
    fi
    if [[ "$level" == "VERBOSE" ]] && [[ "$VERBOSE" != "true" ]] && [[ "$DEBUG" != "true" ]]; then
        return
    fi
    
    local output="[${timestamp}] [${level}] ${message}"
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output=$(jq -n --arg ts "$timestamp" --arg lvl "$level" --arg msg "$message" \
            '{timestamp: $ts, level: $lvl, message: $msg}')
    fi
    
    echo "$output" >&2
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "$output" >> "$LOG_FILE"
    fi
}

log_info() {
    log "INFO" "$@"
}

log_verbose() {
    log "VERBOSE" "$@"
}

log_debug() {
    log "DEBUG" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_warn() {
    log "WARN" "$@"
}

show_usage() {
    cat >&2 <<EOF
PagerDuty to Slack On-Call Sync - v${VERSION}

Usage: $0 [OPTIONS] <PRIMARY_SCHEDULE_ID> <SECONDARY_SCHEDULE_ID> <SLACK_GROUP_HANDLE>

Arguments:
  PRIMARY_SCHEDULE_ID       PagerDuty ID for primary on-call schedule
  SECONDARY_SCHEDULE_ID     PagerDuty ID for secondary on-call schedule
  SLACK_GROUP_HANDLE        Slack user group handle or name to update

Options:
  --dry-run                 Test without making changes
  --cache-ttl SECONDS       Cache TTL in seconds (default: 300)
  --max-retries COUNT       Maximum retry attempts (default: 3)
  --verbose                 Enable verbose logging
  --debug                   Enable debug logging
  --quiet                   Suppress all output except errors
  --json                    Output logs in JSON format
  --log-file PATH           Write logs to file
  --continue-on-error       Continue on recoverable errors
  --health-check            Validate API connectivity and exit
  --config FILE             Load configuration from file
  --version                 Show version and exit
  --help                    Show this help message

Environment Variables:
  PAGER_TOKEN              PagerDuty API token (required)
  SLACK_TOKEN              Slack API token (required)
  CACHE_DIR                Cache directory (default: /tmp/pd2slack-cache)

Examples:
  $0 P123456 P654321 'oncall-team-a'
  $0 --dry-run P123456 P654321 'oncall-team-a'
  $0 --cache-ttl 600 --verbose P123456 P654321 'oncall-team-a'

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --cache-ttl)
                CACHE_TTL="$2"
                shift 2
                ;;
            --max-retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            --debug)
                DEBUG="true"
                VERBOSE="true"
                shift
                ;;
            --quiet)
                QUIET="true"
                shift
                ;;
            --json)
                JSON_OUTPUT="true"
                shift
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            --continue-on-error)
                CONTINUE_ON_ERROR="true"
                shift
                ;;
            --health-check)
                HEALTH_CHECK="true"
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --version)
                echo "v${VERSION}"
                exit 0
                ;;
            --help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit "$EXIT_CONFIG_ERROR"
                ;;
            *)
                # Positional arguments
                if [[ -z "${PRIMARY_SCHEDULE_ID:-}" ]]; then
                    PRIMARY_SCHEDULE_ID="$1"
                elif [[ -z "${SECONDARY_SCHEDULE_ID:-}" ]]; then
                    SECONDARY_SCHEDULE_ID="$1"
                elif [[ -z "${SLACK_TARGET:-}" ]]; then
                    SLACK_TARGET="$1"
                else
                    log_error "Too many arguments"
                    show_usage
                    exit "$EXIT_CONFIG_ERROR"
                fi
                shift
                ;;
        esac
    done
}

validate_config() {
    if [[ -z "$PAGER_TOKEN" ]]; then
        log_error "PAGER_TOKEN environment variable is not set."
        exit "$EXIT_CONFIG_ERROR"
    fi
    
    if [[ -z "$SLACK_TOKEN" ]]; then
        log_error "SLACK_TOKEN environment variable is not set."
        exit "$EXIT_CONFIG_ERROR"
    fi
    
    if [[ "$HEALTH_CHECK" != "true" ]]; then
        if [[ -z "${PRIMARY_SCHEDULE_ID:-}" ]] || [[ -z "${SECONDARY_SCHEDULE_ID:-}" ]] || [[ -z "${SLACK_TARGET:-}" ]]; then
            log_error "Missing required arguments"
            show_usage
            exit "$EXIT_CONFIG_ERROR"
        fi
        
        # Validate schedule ID format (should start with P)
        if [[ ! "$PRIMARY_SCHEDULE_ID" =~ ^P[A-Z0-9]+ ]]; then
            log_warn "PRIMARY_SCHEDULE_ID does not match expected format (P[A-Z0-9]+): $PRIMARY_SCHEDULE_ID"
        fi
        if [[ ! "$SECONDARY_SCHEDULE_ID" =~ ^P[A-Z0-9]+ ]]; then
            log_warn "SECONDARY_SCHEDULE_ID does not match expected format (P[A-Z0-9]+): $SECONDARY_SCHEDULE_ID"
        fi
    fi
}

init_cache() {
    if [[ ! -d "$CACHE_DIR" ]]; then
        log_verbose "Creating cache directory: $CACHE_DIR"
        mkdir -p "$CACHE_DIR"
    fi
}

get_cache_file() {
    local key="$1"
    local hash
    hash=$(echo -n "$key" | md5 2>/dev/null || echo -n "$key" | md5sum | cut -d' ' -f1)
    echo "${CACHE_DIR}/${hash}.cache"
}

get_cached_value() {
    local key="$1"
    local cache_file
    cache_file=$(get_cache_file "$key")
    
    if [[ ! -f "$cache_file" ]]; then
        log_debug "Cache miss: $key"
        return 1
    fi
    
    local cache_time
    cache_time=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)
    local current_time
    current_time=$(date +%s)
    local age=$((current_time - cache_time))
    
    if [[ $age -gt $CACHE_TTL ]]; then
        log_debug "Cache expired (age: ${age}s): $key"
        rm -f "$cache_file"
        return 1
    fi
    
    log_debug "Cache hit (age: ${age}s): $key"
    cat "$cache_file"
    return 0
}

set_cached_value() {
    local key="$1"
    local value="$2"
    local cache_file
    cache_file=$(get_cache_file "$key")
    
    log_debug "Caching value for: $key"
    echo "$value" > "$cache_file"
}

retry_with_backoff() {
    local attempt=0
    local delay="$RETRY_DELAY"
    local max_retries="$MAX_RETRIES"
    
    while [[ $attempt -lt $max_retries ]]; do
        if "$@"; then
            return 0
        fi
        
        attempt=$((attempt + 1))
        if [[ $attempt -lt $max_retries ]]; then
            log_warn "Attempt $attempt failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
    done
    
    log_error "All $max_retries attempts failed"
    return 1
}

api_call() {
    local url="$1"
    shift
    local response
    
    log_debug "API call: $url"
    
    response=$(curl -s --max-time "$API_TIMEOUT" "$@" "$url")
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "API call failed with exit code: $exit_code"
        return 1
    fi
    
    echo "$response"
    return 0
}

get_oncall_user_email() {
    local schedule_id="$1"
    local escalation_level="$2"
    
    local cache_key="oncall:${schedule_id}:${escalation_level}"
    local cached_email
    
    if cached_email=$(get_cached_value "$cache_key"); then
        log_verbose "Using cached on-call user for schedule ${schedule_id} (level ${escalation_level})"
        echo "$cached_email"
        return 0
    fi
    
    log_info "Fetching on-call user for schedule ${schedule_id} (level ${escalation_level})..."
    
    # Get the user self-link from oncalls
    local user_url
    local oncalls_response
    
    if ! oncalls_response=$(retry_with_backoff api_call "${PAGER_API_BASE}/oncalls" \
        -G -H "Authorization: Token token=${PAGER_TOKEN}" \
        -H "Accept: application/vnd.pagerduty+json;version=2" \
        --data-urlencode "time_zone=UTC" \
        --data-urlencode "schedule_ids[]=${schedule_id}"); then
        log_error "Failed to fetch on-call data for schedule ${schedule_id}"
        return 1
    fi
    
    user_url=$(echo "$oncalls_response" | jq -r ".oncalls[] | select(.escalation_level == ${escalation_level}) | .user.self // empty" | head -n 1)
    
    if [[ -z "$user_url" ]]; then
        log_error "No on-call user found for schedule ${schedule_id} at escalation level ${escalation_level}."
        return 1
    fi
    
    log_debug "Found user URL: $user_url"
    
    # Get the user email
    local email
    local user_response
    
    if ! user_response=$(retry_with_backoff api_call "$user_url" \
        -H "Authorization: Token token=${PAGER_TOKEN}" \
        -H "Accept: application/vnd.pagerduty+json;version=2"); then
        log_error "Failed to fetch user details from ${user_url}"
        return 1
    fi
    
    email=$(echo "$user_response" | jq -r '.user.email // empty')
    
    if [[ -z "$email" ]]; then
        log_error "Could not retrieve email for user at ${user_url}."
        return 1
    fi
    
    log_info "Found on-call user: $email"
    
    # Cache the result
    set_cached_value "$cache_key" "$email"
    
    echo "$email"
}

get_slack_user_id() {
    local email="$1"
    
    local cache_key="slack:user:${email}"
    local cached_id
    
    if cached_id=$(get_cached_value "$cache_key"); then
        log_verbose "Using cached Slack user ID for: ${email}"
        echo "$cached_id"
        return 0
    fi
    
    log_info "Looking up Slack user ID for email: ${email}..."
    
    local user_id
    local lookup_response
    
    if ! lookup_response=$(retry_with_backoff api_call "${SLACK_API_BASE}/users.lookupByEmail" \
        -H "Authorization: Bearer ${SLACK_TOKEN}" \
        -G --data-urlencode "email=${email}"); then
        log_error "Failed to lookup Slack user for email ${email}"
        return 1
    fi
    
    local ok
    ok=$(echo "$lookup_response" | jq -r '.ok')
    
    if [[ "$ok" != "true" ]]; then
        local error
        error=$(echo "$lookup_response" | jq -r '.error')
        log_error "Slack API error: ${error}"
        return 1
    fi
    
    user_id=$(echo "$lookup_response" | jq -r '.user.id // empty')
    
    if [[ -z "$user_id" ]]; then
        log_error "Slack user not found for email ${email}."
        return 1
    fi
    
    log_info "Found Slack user: ${user_id}"
    
    # Cache the result
    set_cached_value "$cache_key" "$user_id"
    
    echo "$user_id"
}

get_slack_group_id() {
    local target="$1"
    
    local cache_key="slack:group:${target}"
    local cached_id
    
    if cached_id=$(get_cached_value "$cache_key"); then
        log_verbose "Using cached Slack group ID for: ${target}"
        echo "$cached_id"
        return 0
    fi
    
    log_info "Finding Slack user group ID for: ${target}..."
    
    local group_id
    local groups_response
    
    if ! groups_response=$(retry_with_backoff api_call "${SLACK_API_BASE}/usergroups.list" \
        -H "Authorization: Bearer ${SLACK_TOKEN}"); then
        log_error "Failed to list Slack user groups"
        return 1
    fi
    
    group_id=$(echo "$groups_response" | jq -r --arg target "$target" '.usergroups[] | select(.handle == $target or .name == $target) | .id' | head -n 1)
    
    if [[ -z "$group_id" ]]; then
        # Try a partial match if exact match fails
        log_debug "Exact match failed, trying partial match..."
        group_id=$(echo "$groups_response" | jq -r --arg target "$target" '.usergroups[] | select(.name | contains($target)) | .id' | head -n 1)
    fi
    
    if [[ -z "$group_id" ]]; then
        log_error "Could not find Slack user group with handle or name matching '${target}'."
        return 1
    fi
    
    log_info "Found Slack group: ${group_id}"
    
    # Cache the result
    set_cached_value "$cache_key" "$group_id"
    
    echo "$group_id"
}

update_slack_group() {
    local group_id="$1"
    local user_ids="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update Slack group ${group_id} with members: ${user_ids}"
        return 0
    fi
    
    log_info "Updating Slack group ${group_id} with members: ${user_ids}..."
    
    local update_response
    
    if ! update_response=$(retry_with_backoff api_call "${SLACK_API_BASE}/usergroups.users.update" \
        -X POST -H "Authorization: Bearer ${SLACK_TOKEN}" \
        -H "Content-Type: application/json; charset=utf-8" \
        --data "{\"usergroup\": \"${group_id}\", \"users\": \"${user_ids}\"}"); then
        log_error "Failed to update Slack group"
        return 1
    fi
    
    local ok
    ok=$(echo "$update_response" | jq -r '.ok')
    
    if [[ "$ok" == "true" ]]; then
        log_info "Success! Slack group updated."
        return 0
    else
        local error
        error=$(echo "$update_response" | jq -r '.error')
        log_error "Failed to update Slack group. API responded with: ${error}"
        return 1
    fi
}

health_check() {
    log_info "Running health check..."
    
    local errors=0
    
    # Check PagerDuty API
    log_info "Testing PagerDuty API connectivity..."
    if api_call "${PAGER_API_BASE}/abilities" \
        -H "Authorization: Token token=${PAGER_TOKEN}" \
        -H "Accept: application/vnd.pagerduty+json;version=2" > /dev/null; then
        log_info "✓ PagerDuty API: OK"
    else
        log_error "✗ PagerDuty API: FAILED"
        errors=$((errors + 1))
    fi
    
    # Check Slack API
    log_info "Testing Slack API connectivity..."
    local auth_response
    if auth_response=$(api_call "${SLACK_API_BASE}/auth.test" \
        -H "Authorization: Bearer ${SLACK_TOKEN}"); then
        local ok
        ok=$(echo "$auth_response" | jq -r '.ok')
        if [[ "$ok" == "true" ]]; then
            log_info "✓ Slack API: OK"
        else
            log_error "✗ Slack API: Authentication failed"
            errors=$((errors + 1))
        fi
    else
        log_error "✗ Slack API: FAILED"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "Health check passed!"
        return 0
    else
        log_error "Health check failed with $errors error(s)"
        return 1
    fi
}

# --- Main ---

main() {
    local start_time
    start_time=$(date +%s)
    
    # Parse arguments
    parse_args "$@"
    
    # Validate configuration
    validate_config
    
    # Initialize cache
    init_cache
    
    # Health check mode
    if [[ "$HEALTH_CHECK" == "true" ]]; then
        if health_check; then
            exit "$EXIT_SUCCESS"
        else
            exit "$EXIT_API_ERROR"
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== DRY RUN MODE ==="
    fi
    
    log_info "Starting PagerDuty to Slack sync..."
    log_verbose "Primary Schedule: $PRIMARY_SCHEDULE_ID"
    log_verbose "Secondary Schedule: $SECONDARY_SCHEDULE_ID"
    log_verbose "Slack Target: $SLACK_TARGET"
    
    # 1. Get Emails from PagerDuty
    local primary_email secondary_email
    
    if ! primary_email=$(get_oncall_user_email "$PRIMARY_SCHEDULE_ID" "$ESCALATION_LEVEL_PRIMARY"); then
        log_error "Failed to get primary on-call user"
        exit "$EXIT_API_ERROR"
    fi
    
    if ! secondary_email=$(get_oncall_user_email "$SECONDARY_SCHEDULE_ID" "$ESCALATION_LEVEL_SECONDARY"); then
        if [[ "$CONTINUE_ON_ERROR" == "true" ]]; then
            log_warn "Failed to get secondary on-call user, continuing with primary only"
            secondary_email=""
        else
            log_error "Failed to get secondary on-call user"
            exit "$EXIT_API_ERROR"
        fi
    fi
    
    # 2. Get Slack IDs
    local primary_slack_id secondary_slack_id
    
    if ! primary_slack_id=$(get_slack_user_id "$primary_email"); then
        log_error "Failed to get Slack ID for primary user"
        exit "$EXIT_API_ERROR"
    fi
    
    if [[ -n "$secondary_email" ]]; then
        if ! secondary_slack_id=$(get_slack_user_id "$secondary_email"); then
            if [[ "$CONTINUE_ON_ERROR" == "true" ]]; then
                log_warn "Failed to get Slack ID for secondary user, continuing with primary only"
                secondary_slack_id=""
            else
                log_error "Failed to get Slack ID for secondary user"
                exit "$EXIT_API_ERROR"
            fi
        fi
    fi
    
    # 3. Get Slack Group ID
    local usergroup_id
    if ! usergroup_id=$(get_slack_group_id "$SLACK_TARGET"); then
        log_error "Failed to get Slack group ID"
        exit "$EXIT_API_ERROR"
    fi
    
    # 4. Update Slack Group
    local user_ids="$primary_slack_id"
    if [[ -n "$secondary_slack_id" ]]; then
        user_ids="${user_ids},${secondary_slack_id}"
    fi
    
    if ! update_slack_group "$usergroup_id" "$user_ids"; then
        log_error "Failed to update Slack group"
        exit "$EXIT_API_ERROR"
    fi
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "Sync completed successfully in ${duration}s"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== DRY RUN COMPLETE ==="
    fi
    
    exit "$EXIT_SUCCESS"
}

# Run main function
main "$@"
