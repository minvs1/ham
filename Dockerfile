FROM --platform=$TARGETOS/$TARGETARCH alpine:3.14

RUN apk add --no-cache bash git jq wget

COPY entrypoint.sh /usr/local/bin/ham.sh
RUN chmod +x /usr/local/bin/ham.sh

ENTRYPOINT ["/usr/local/bin/ham.sh"]
