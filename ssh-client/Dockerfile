FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    openssh-client \
  && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/ssh-client-entrypoint
RUN chmod 0755 /usr/local/bin/ssh-client-entrypoint

USER nobody:nogroup

ENTRYPOINT ["/usr/local/bin/ssh-client-entrypoint"]
