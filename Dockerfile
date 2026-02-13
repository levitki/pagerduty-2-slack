FROM alpine:3.19

# Install required packages
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    coreutils \
    && rm -rf /var/cache/apk/*

# Create working directory
WORKDIR /app

# Copy the script
COPY push_into_slack_group.sh /app/

# Make script executable
RUN chmod +x /app/push_into_slack_group.sh

# Set bash as default shell
SHELL ["/bin/bash", "-c"]

ENTRYPOINT ["/app/push_into_slack_group.sh"]
