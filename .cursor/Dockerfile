# Cursor cloud-agent base image. System packages and toolchains only.
# Cursor checks out the repository after the image is built; do not COPY the app.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    BUNDLE_PATH=/usr/local/bundle

COPY bootstrap-system.sh /tmp/bootstrap-system.sh
RUN bash /tmp/bootstrap-system.sh && rm /tmp/bootstrap-system.sh

USER ubuntu
WORKDIR /workspace
