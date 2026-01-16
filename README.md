# PagerDuty to Slack On-Call Sync

This tool automates the synchronization of PagerDuty on-call schedules with Slack user groups. It ensures that mentions of a Slack user group (e.g., `@oncall-team-a`) always notify the current primary and secondary on-call engineers.

## Features

- Fetches current on-call users from PagerDuty based on specific schedule IDs.
- Maps PagerDuty users to Slack users via their email addresses.
- Updates a specified Slack user group with the identified users.
- Supports primary and secondary on-call levels.

## Prerequisites

- **PagerDuty API Token**: A read-only API token from PagerDuty.
- **Slack API Token**: A Slack Bot or User token with the following scopes:
    - `users:read`
    - `users:read.email`
    - `usergroups:read`
    - `usergroups:write`
- **Tools**: `curl` and `jq` must be installed on the system running the script.

## Environment Variables

The script requires the following environment variables to be set:

| Variable | Description |
| :--- | :--- |
| `PAGER_TOKEN` | PagerDuty REST API token. |
| `SLACK_TOKEN` | Slack API token (Bearer token). |

## Usage

```bash
./push_into_slack_group.sh <PRIMARY_SCHEDULE_ID> <SECONDARY_SCHEDULE_ID> <SLACK_GROUP_HANDLE>
```

### Arguments:

1. **`PRIMARY_SCHEDULE_ID`**: The PagerDuty ID for the primary on-call schedule.
2. **`SECONDARY_SCHEDULE_ID`**: The PagerDuty ID for the secondary on-call schedule.
3. **`SLACK_GROUP_HANDLE`**: The handle (e.g., `oncall-devops`) or the name of the Slack user group to update.

### Example:

```bash
export PAGER_TOKEN="your-pagerduty-token"
export SLACK_TOKEN="xoxb-your-slack-token"

./push_into_slack_group.sh P123456 P654321 'oncall-team-a'
```

## GitLab CI Integration

This script is designed to be run periodically (e.g., via a scheduled pipeline) to keep Slack groups in sync with PagerDuty.

See `.gitlab-ci.yml` for an example configuration. Ensure you define `PAGER_TOKEN` and `SLACK_TOKEN` as CI/CD variables in your GitLab project.
