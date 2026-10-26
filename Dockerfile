# Linux check environment: Free Pascal 3.2.2 + libcurl + bash.
# Source is mounted at /workspace (see docker-compose.yaml), nothing is copied in.
FROM ubuntu:24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    SHELL=/bin/bash \
    LANG=C.UTF-8

# fpc = Free Pascal 3.2.2, libcurl4-openssl-dev provides the libcurl.so that the libcurl unit loads
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl fpc libcurl4-openssl-dev python3 \
 && rm -rf /var/lib/apt/lists/*

# non-root user whose ids match the host user, so files written to the mounted
# project are not owned by root; bash is its login shell
ARG HOST_UID=1000
ARG HOST_GID=1000
RUN (userdel -r ubuntu 2>/dev/null || true) \
 && (getent group "${HOST_GID}" >/dev/null || groupadd -g "${HOST_GID}" dev) \
 && useradd -m -s /bin/bash -u "${HOST_UID}" -g "${HOST_GID}" dev

USER dev
WORKDIR /workspace
CMD ["/bin/bash"]
