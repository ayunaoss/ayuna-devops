# syntax=docker/dockerfile:1.4

## Valid values for AYUNA_OCI: oci-py, oci-js, oci-go, oci-pyjs, oci-builder
ARG AYUNA_OCI=oci-builder
ARG AYUNA_PYTHON_VER=3.12.14
ARG AYUNA_NODEJS_VER=24.20.0
ARG AYUNA_GOLANG_VER=1.27.0

ARG AYUNA_UID=1001
ARG AYUNA_GID=1001
ARG AYUNA_HOME=/opt/ayuna
ARG AYUNA_UDK=${AYUNA_HOME}/udk

##########################################
## The builder image to build the tools ##
##########################################
FROM ubuntu:24.04 AS ayuna-builder

ARG AYUNA_PYTHON_VER
ARG AYUNA_NODEJS_VER
ARG AYUNA_GOLANG_VER
ARG AYUNA_UDK

COPY ./scripts /tmp/scripts

RUN set -eu; \
    echo "Installing basic tools..."; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    tar \
    unzip \
    wget; \
    sync; \
    apt-get autoremove --purge -y; \
    apt-get clean; \
    dpkg --configure -a; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    echo "Setting up python devkit..."; \
    /bin/bash /tmp/scripts/devkit-setup.sh --udk=${AYUNA_UDK} --kit=python --version=${AYUNA_PYTHON_VER}; \
    echo "Setting up node.js devkit..."; \
    /bin/bash /tmp/scripts/devkit-setup.sh --udk=${AYUNA_UDK} --kit=nodejs --version=${AYUNA_NODEJS_VER}; \
    echo "Setting up golang devkit..."; \
    /bin/bash /tmp/scripts/devkit-setup.sh --udk=${AYUNA_UDK} --kit=golang --version=${AYUNA_GOLANG_VER}; \
    rm -rf /root/.cache

##### Base image with required packages and user #####
FROM ubuntu:24.04 AS ayuna-ocibase

ARG TIMEZONE=UTC
ARG AYUNA_UID
ARG AYUNA_GID
ARG AYUNA_HOME

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PYTHONUNBUFFERED=1

RUN set -eu; \
    echo "Setting up base system with user, timezone and locales..."; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y \
    bind9-dnsutils \
    ca-certificates \
    curl \
    gnupg \
    htop \
    iproute2 \
    jq \
    libcap2-bin \
    libpq5 \
    libsm6 \
    locales \
    netbase \
    procps \
    tar \
    telnet \
    tree \
    tzdata \
    unzip \
    wget \
    xz-utils; \
    sync; \
    apt-get autoremove --purge -y; \
    apt-get clean; \
    dpkg --configure -a; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    sync; \
    ln -snf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime; \
    dpkg-reconfigure -f noninteractive tzdata; \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen; \
    sync && locale-gen; \
    update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8; \
    update-ca-certificates; \
    groupadd --gid ${AYUNA_UID} ayuna; \
    adduser --uid ${AYUNA_UID} --gid ${AYUNA_UID} --disabled-password \
    --comment "AyunaIO User" --home ${AYUNA_HOME} ayuna; \
    mkdir -p ${AYUNA_HOME}/.config ${AYUNA_HOME}/.local/bin ${AYUNA_HOME}/.local/lib; \
    chown -R ayuna:ayuna ${AYUNA_HOME}

USER ayuna
WORKDIR ${AYUNA_HOME}

COPY --chown=ayuna:ayuna ./skel/profile ${AYUNA_HOME}/.profile
COPY --chown=ayuna:ayuna ./skel/bashrc ${AYUNA_HOME}/.bashrc

RUN set -eu; \
    chmod 644 ${AYUNA_HOME}/.profile ${AYUNA_HOME}/.bashrc; \
    echo "Installing uv python package manager..."; \
    curl -LsSf https://astral.sh/uv/install.sh | sh

##### Setup image for oci-py #####
FROM ayuna-ocibase AS ayuna-oci-py

ARG AYUNA_PYTHON_VER
ARG AYUNA_UDK

ENV PATH=${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}/bin:${PATH}
ENV LD_LIBRARY_PATH=${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}/lib:${LD_LIBRARY_PATH}
ENV PKG_CONFIG_PATH=${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}/lib/pkgconfig:${PKG_CONFIG_PATH}

USER root
WORKDIR /

COPY --from=ayuna-builder ${AYUNA_UDK}/py-${AYUNA_PYTHON_VER} ${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}

##### Setup image for oci-js #####
FROM ayuna-ocibase AS ayuna-oci-js

ARG AYUNA_NODEJS_VER
ARG AYUNA_UDK

ENV PATH=${AYUNA_UDK}/node-${AYUNA_NODEJS_VER}/bin:${PATH}

USER root
WORKDIR /

COPY --from=ayuna-builder ${AYUNA_UDK}/node-${AYUNA_NODEJS_VER} ${AYUNA_UDK}/node-${AYUNA_NODEJS_VER}

##### Setup image for oci-go #####
FROM ayuna-ocibase AS ayuna-oci-go

ARG AYUNA_GOLANG_VER
ARG AYUNA_UDK

ENV PATH=${AYUNA_UDK}/go-${AYUNA_GOLANG_VER}/bin:${AYUNA_UDK}/goext/bin:${PATH}
ENV GOROOT=${AYUNA_UDK}/go-${AYUNA_GOLANG_VER}
ENV GOPATH=${AYUNA_UDK}/goext

USER root
WORKDIR /

COPY --from=ayuna-builder ${AYUNA_UDK}/go-${AYUNA_GOLANG_VER} ${AYUNA_UDK}/go-${AYUNA_GOLANG_VER}
COPY --from=ayuna-builder ${AYUNA_UDK}/goext ${AYUNA_UDK}/goext

##### Setup image for oci-pyjs #####
FROM ayuna-ocibase AS ayuna-oci-pyjs

ARG AYUNA_PYTHON_VER
ARG AYUNA_NODEJS_VER
ARG AYUNA_UDK

ENV PATH=${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}/bin:${PATH}
ENV PATH=${AYUNA_UDK}/node-${AYUNA_NODEJS_VER}/bin:${PATH}
ENV LD_LIBRARY_PATH=${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}/lib:${LD_LIBRARY_PATH}
ENV PKG_CONFIG_PATH=${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}/lib/pkgconfig:${PKG_CONFIG_PATH}

USER root
WORKDIR /

COPY --from=ayuna-builder ${AYUNA_UDK}/py-${AYUNA_PYTHON_VER} ${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}
COPY --from=ayuna-builder ${AYUNA_UDK}/node-${AYUNA_NODEJS_VER} ${AYUNA_UDK}/node-${AYUNA_NODEJS_VER}

##### Setup image for oci-builder #####
FROM ayuna-ocibase AS ayuna-oci-builder

ARG AYUNA_PYTHON_VER
ARG AYUNA_NODEJS_VER
ARG AYUNA_GOLANG_VER
ARG AYUNA_UDK

ENV PATH=${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}/bin:${PATH}
ENV PATH=${AYUNA_UDK}/node-${AYUNA_NODEJS_VER}/bin:${PATH}
ENV PATH=${AYUNA_UDK}/go-${AYUNA_GOLANG_VER}/bin:${AYUNA_UDK}/goext/bin:${PATH}
ENV GOROOT=${AYUNA_UDK}/go-${AYUNA_GOLANG_VER}
ENV GOPATH=${AYUNA_UDK}/goext
ENV LD_LIBRARY_PATH=${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}/lib:${LD_LIBRARY_PATH}
ENV PKG_CONFIG_PATH=${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}/lib/pkgconfig:${PKG_CONFIG_PATH}

USER root
WORKDIR /

COPY --from=ayuna-builder ${AYUNA_UDK}/py-${AYUNA_PYTHON_VER} ${AYUNA_UDK}/py-${AYUNA_PYTHON_VER}
COPY --from=ayuna-builder ${AYUNA_UDK}/node-${AYUNA_NODEJS_VER} ${AYUNA_UDK}/node-${AYUNA_NODEJS_VER}
COPY --from=ayuna-builder ${AYUNA_UDK}/go-${AYUNA_GOLANG_VER} ${AYUNA_UDK}/go-${AYUNA_GOLANG_VER}
COPY --from=ayuna-builder ${AYUNA_UDK}/goext ${AYUNA_UDK}/goext

RUN set -eu; \
    echo "Setting up OCI-BUILDER target..."; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
    apt-transport-https \
    build-essential \
    ca-certificates \
    dpkg-dev \
    enchant-2 \
    ffmpeg \
    g++ \
    git \
    libbluetooth-dev \
    libbz2-dev \
    libc6-dev \
    libdb-dev \
    libffi-dev \
    libgdbm-dev \
    libgl-dev \
    libkrb5-dev \
    liblzma-dev \
    libncursesw5-dev \
    libpq-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    libtesseract-dev \
    libturbojpeg0-dev \
    libxext6 \
    libzstd-dev \
    make \
    netbase \
    swig \
    tesseract-ocr \
    tk-dev \
    tzdata \
    uuid-dev \
    wget \
    xz-utils \
    zlib1g-dev \
    ; \
    ldconfig; \
    apt-get clean; \
    apt-get autoremove --purge -y; \
    dpkg --configure -a; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

##################################
## Finalize the ayuna-oci image ##
##################################
FROM ayuna-${AYUNA_OCI} AS ayuna-oci

ARG AYUNA_HOME
ARG AYUNA_UDK

ENV PATH=${AYUNA_HOME}/.local/bin:${PATH}
ENV LD_LIBRARY_PATH=${AYUNA_HOME}/.local/lib:${LD_LIBRARY_PATH}
ENV PKG_CONFIG_PATH=${AYUNA_HOME}/.local/lib/pkgconfig:${PKG_CONFIG_PATH}

USER root
WORKDIR /

COPY --from=ayuna-builder ${AYUNA_UDK}/.distrc ${AYUNA_UDK}/.distrc

RUN rm -rf /root/.cache; \
    echo "export PATH=${AYUNA_HOME}/.local/bin:\$PATH" >> ${AYUNA_UDK}/.distrc; \
    echo "export LD_LIBRARY_PATH=${AYUNA_HOME}/.local/lib:\$LD_LIBRARY_PATH" >> ${AYUNA_UDK}/.distrc; \
    echo "export PKG_CONFIG_PATH=${AYUNA_HOME}/.local/lib/pkgconfig:\$PKG_CONFIG_PATH" >> ${AYUNA_UDK}/.distrc; \
    chown -R ayuna:ayuna ${AYUNA_HOME}

CMD ["/bin/bash"]
