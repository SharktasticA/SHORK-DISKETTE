FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y bc bison bzip2 cpio dosfstools flex git make nasm python3 python-is-python3 sudo syslinux uuid-dev wget xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/shork-diskette

ENTRYPOINT ["/bin/bash", "/var/shork-diskette/build.sh"]