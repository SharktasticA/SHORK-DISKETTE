FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y bc bison bzip2 dosfstools flex git make sudo syslinux wget xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/shork-diskette

ENTRYPOINT ["/bin/bash", "/var/shork-diskette/build.sh"]