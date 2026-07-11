# syntax=docker/dockerfile:1.7

ARG DEBIAN_VERSION=12-slim
ARG JAVA_MAJOR_VERSION=17

FROM debian:${DEBIAN_VERSION} AS installer

ARG SAVAPAGE_VERSION=1.6.0-final
ARG SAVAPAGE_DOWNLOAD_URL=https://www.savapage.org/download/installer/savapage-setup-1.6.0-final-linux-x64.bin
ARG SAVAPAGE_DOWNLOAD_SHA256=b5c388a35b707946ca8f4264605b6b252c6620769e2e32dbf910425fd381433c
ARG JAVA_MAJOR_VERSION

RUN apt-get -o Acquire::ForceIPv4=true -o Acquire::Retries=5 update \
    && apt-get install --yes --no-install-recommends \
        binutils \
        ca-certificates \
        cpio \
        cups \
        cups-bsd \
        curl \
        debianutils \
        gnupg \
        gzip \
        imagemagick \
        libheif-examples \
        librsvg2-bin \
        openjdk-${JAVA_MAJOR_VERSION}-jdk-headless \
        perl \
        poppler-utils \
        qpdf \
    && rm -rf /var/lib/apt/lists/*

RUN test -n "${SAVAPAGE_VERSION}" \
    && test -n "${SAVAPAGE_DOWNLOAD_URL}" \
    && test -n "${SAVAPAGE_DOWNLOAD_SHA256}" \
    && curl --fail --location --retry 3 --output /tmp/savapage-setup.bin "${SAVAPAGE_DOWNLOAD_URL}" \
    && printf '%s  %s\n' "${SAVAPAGE_DOWNLOAD_SHA256}" /tmp/savapage-setup.bin | sha256sum --check --strict

RUN groupadd --gid 1000 savapage \
    && useradd --system --uid 1000 --gid 1000 --home-dir /opt/savapage --shell /bin/bash savapage \
    && install --directory --owner savapage --group savapage --mode 0755 /opt/savapage \
    && mv /tmp/savapage-setup.bin /opt/savapage/savapage-setup.bin \
    && chown savapage:savapage /opt/savapage/savapage-setup.bin \
    && cd /opt/savapage \
    && runuser --user savapage -- sh ./savapage-setup.bin -n \
    && test -x /opt/savapage/server/bin/linux-x64/app-server \
    && test -x /opt/savapage/providers/cups/linux-x64/savapage-notifier \
    && rm -f /opt/savapage/savapage-setup.bin \
    && rm -f /opt/savapage/server/data/encryption.properties \
    && printf '%s\n' "${SAVAPAGE_VERSION}" > /opt/savapage/.image-version

FROM debian:${DEBIAN_VERSION} AS runtime

ARG SAVAPAGE_VERSION=1.6.0-final
ARG JAVA_MAJOR_VERSION
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown

# Serialize package downloads behind the installer stage. This avoids two
# concurrent apt transactions against the Debian mirrors in constrained CI.
COPY --from=installer /opt/savapage/.image-version /tmp/installer-ready

LABEL org.opencontainers.image.title="SavaPage for TrueNAS" \
      org.opencontainers.image.description="SavaPage with local CUPS for TrueNAS SCALE and Docker Compose" \
      org.opencontainers.image.url="https://github.com/digikwal/savapage-truenas" \
      org.opencontainers.image.source="https://github.com/digikwal/savapage-truenas" \
      org.opencontainers.image.documentation="https://github.com/digikwal/savapage-truenas/tree/main/docs" \
      org.opencontainers.image.licenses="GPL-3.0-only AND AGPL-3.0-or-later" \
      org.opencontainers.image.version="${SAVAPAGE_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

RUN apt-get -o Acquire::ForceIPv4=true -o Acquire::Retries=5 update \
    && apt-get install --yes --no-install-recommends \
        avahi-daemon \
        avahi-utils \
        binutils \
        ca-certificates \
        cups \
        cups-bsd \
        cups-client \
        cups-filters \
        cups-ipp-utils \
        curl \
        dbus \
        debianutils \
        ghostscript \
        gnupg \
        gzip \
        imagemagick \
        iproute2 \
        libheif-examples \
        libnss-mdns \
        librsvg2-bin \
        netcat-openbsd \
        openjdk-${JAVA_MAJOR_VERSION}-jre-headless \
        perl \
        poppler-utils \
        postgresql-client \
        procps \
        qpdf \
        tini \
        usbutils \
    && rm -rf /var/lib/apt/lists/* /tmp/installer-ready

RUN groupadd --gid 1000 savapage \
    && useradd --system --uid 1000 --gid 1000 --home-dir /opt/savapage --shell /bin/bash savapage \
    && usermod --append --groups lp,lpadmin savapage

COPY --from=installer --chown=savapage:savapage /opt/savapage /opt/savapage
COPY scripts/entrypoint.sh /usr/local/bin/savapage-entrypoint
COPY scripts/healthcheck-savapage.sh /usr/local/bin/healthcheck-savapage
COPY scripts/healthcheck-cups.sh /usr/local/bin/healthcheck-cups
COPY scripts/diagnostics.sh /usr/local/bin/savapage-diagnostics
COPY scripts/cups-backend-test-file.sh /usr/lib/cups/backend/savapage-ci-file

RUN install --directory --mode 0755 /usr/share/savapage/default-data /usr/share/savapage/default-cups \
    && cp -a /opt/savapage/server/data/. /usr/share/savapage/default-data/ \
    && cp -a /etc/cups/. /usr/share/savapage/default-cups/ \
    && install --owner root --group root --mode 0700 \
        /opt/savapage/providers/cups/linux-x64/savapage-notifier \
        /usr/lib/cups/notifier/savapage \
    && chown root:root /opt/savapage/server/bin/linux-x64/savapage-pam \
    && chmod 0511 /opt/savapage/server/bin/linux-x64/savapage-pam \
    && cp /etc/pam.d/passwd /etc/pam.d/savapage \
    && chmod 0755 /usr/local/bin/savapage-entrypoint \
        /usr/local/bin/healthcheck-savapage \
        /usr/local/bin/healthcheck-cups \
        /usr/local/bin/savapage-diagnostics \
    && chmod 0755 /usr/lib/cups/backend/savapage-ci-file

ENV SAVAPAGE_NS=SP_ \
    SP_CONTAINER=DOCKER \
    SAVAPAGE_VERSION=${SAVAPAGE_VERSION} \
    JAVA_HOME=/usr/lib/jvm/java-${JAVA_MAJOR_VERSION}-openjdk-amd64

EXPOSE 631 8631 8632 8633 9100

VOLUME ["/opt/savapage/server/data", "/opt/savapage/server/logs", "/etc/cups", "/var/lib/cups", "/var/cache/cups", "/var/spool/cups"]

HEALTHCHECK --interval=30s --timeout=15s --start-period=180s --retries=5 \
    CMD ["/usr/local/bin/healthcheck-savapage"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/savapage-entrypoint"]
