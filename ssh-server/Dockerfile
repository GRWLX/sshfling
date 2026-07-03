FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    openssh-server \
    procps \
    tini \
  && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash deploy \
  && usermod --password "$(openssl passwd -6 "$(openssl rand -base64 32)")" deploy \
  && mkdir -p /run/sshd /home/deploy/.ssh \
  && chown -R deploy:deploy /home/deploy/.ssh \
  && chmod 0700 /home/deploy/.ssh

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/ssh-server-entrypoint
COPY limited-session.sh /usr/local/bin/limited-session

RUN chmod 0755 /usr/local/bin/ssh-server-entrypoint /usr/local/bin/limited-session

EXPOSE 22

ENTRYPOINT ["tini", "--", "/usr/local/bin/ssh-server-entrypoint"]
