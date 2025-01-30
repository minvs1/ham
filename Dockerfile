FROM --platform=$TARGETOS/$TARGETARCH alpine:3.14

RUN apk add --no-cache wget bash jq

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
