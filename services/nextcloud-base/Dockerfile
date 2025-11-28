# syntax=docker/dockerfile:1.7

# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-debian"
ARG BASE_RUNTIME_IMAGE="php:8.3-apache-trixie"

ARG TLS_ENABLED="false"
ARG TLS_MODE="disabled"
ARG TLS_CERT_NAME=""
ARG TLS_CA_NAME=""

FROM ${COMMON_TOOLS_IMAGE} AS common-tools

FROM ${BASE_RUNTIME_IMAGE}

ARG TLS_ENABLED="false"
ARG TLS_MODE="disabled"
ARG TLS_CERT_NAME=""
ARG TLS_CA_NAME=""
ARG COMMON_TOOLS_IMAGE

ENV PHP_MEMORY_LIMIT=512M
ENV PHP_UPLOAD_LIMIT=512M
ENV PHP_OPCACHE_MEMORY_CONSUMPTION=128
ENV APACHE_BODY_LIMIT=1073741824

RUN --mount=type=cache,id=common-tools-debian-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=common-tools-debian-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install \
    --no-install-recommends \
    --assume-yes \
    git \
    vim \
    curl \
    bzip2 \
    rsync \
    iproute2 \
    busybox-static \
    libldap-common \
    ca-certificates \
    libapache2-mod-security2 \
    libmagickcore-7.q16-10-extra;

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Create cron directory and add cron job
RUN mkdir -p /var/spool/cron/crontabs; \
    echo '*/5 * * * * php -f /var/www/html/cron.php' > /var/spool/cron/crontabs/www-data

# Install build dependencies
RUN --mount=type=cache,id=common-tools-debian-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=common-tools-debian-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    set -ex; \
    savedAptMark="$(apt-mark showmanual)"; \
    echo "$savedAptMark" > /tmp/saved-apt-mark; \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    apt-get update; \
    apt-get install \
    --no-install-recommends \
    --assume-yes \
    libcurl4-openssl-dev \
    libevent-dev \
    libfreetype6-dev \
    libgmp-dev \
    libicu-dev \
    libjpeg-dev \
    libldap2-dev \
    libmagickwand-dev \
    libmemcached-dev \
    libpng-dev \
    libpq-dev \
    libwebp-dev \
    libxml2-dev \
    libzip-dev;

# Configure and install PHP extensions
RUN --mount=type=cache,id=nextcloud-php-ext-build,target=/usr/src/php/ext,sharing=locked \
    debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
    docker-php-ext-configure ftp --with-openssl-dir=/usr; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-configure ldap --with-libdir="lib/$debMultiarch"; \
    docker-php-ext-install -j "$(nproc)" \
    bcmath \
    exif \
    ftp \
    gd \
    gmp \
    intl \
    ldap \
    opcache \
    pcntl \
    pdo_mysql \
    pdo_pgsql \
    sysvsem \
    zip;

# Install PECL extensions
RUN --mount=type=cache,id=nextcloud-pecl-downloads,target=/tmp/pear/download,sharing=locked \
    pecl install APCu-5.1.27; \
    pecl install igbinary-3.2.16; \
    pecl install imagick-3.8.0; \
    pecl install memcached-3.4.0 \
    --configureoptions 'enable-memcached-igbinary="yes"'; \
    pecl install redis-6.3.0 \
    --configureoptions 'enable-redis-igbinary="yes" enable-redis-zstd="yes" enable-redis-lz4="yes"';

# Enable PHP extensions
RUN docker-php-ext-enable \
    apcu \
    igbinary \
    imagick \
    memcached \
    redis;

# apt-mark operations
RUN savedAptMark="$(cat /tmp/saved-apt-mark)"; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
    | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); print so }' \
    | sort -u \
    | xargs -r dpkg-query --search \
    | cut -d: -f1 \
    | sort -u \
    | xargs -rt apt-mark manual

# Cleanup, separate to preserve cache mount contents
RUN rm -r /tmp/pear

# Purge build dependencies in separate RUN to avoid cache mount interference
RUN apt-get purge -y \
    --auto-remove \
    -o APT::AutoRemove::RecommendsImportant=false; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN { \
    echo 'SecStatusEngine Off'; \
    echo 'SecRuleEngine On'; \
    echo 'SecAuditEngine On'; \
    echo 'SecAuditLog /var/log/apache2/modsec_audit.log'; \
    echo 'SecRequestBodyAccess on'; \
    echo 'SecResponseBodyAccess On'; \
    echo 'SecAuditLogParts ABIJEFHZ'; \
    } > "/etc/modsecurity/modsecurity.conf"

# Configure PHP (opcache, apcu, nextcloud settings)
RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.interned_strings_buffer=32'; \
    echo 'opcache.max_accelerated_files=10000'; \
    echo 'opcache.memory_consumption=${PHP_OPCACHE_MEMORY_CONSUMPTION}'; \
    echo 'opcache.save_comments=1'; \
    echo 'opcache.revalidate_freq=60'; \
    echo 'opcache.jit=1255'; \
    echo 'opcache.jit_buffer_size=128M'; \
    } > "${PHP_INI_DIR}/conf.d/opcache-recommended.ini"; \
    echo 'apc.enable_cli=1' >> "${PHP_INI_DIR}/conf.d/docker-php-ext-apcu.ini"; \
    { \
    echo 'apc.serializer=igbinary'; \
    echo 'session.serialize_handler=igbinary'; \
    } >> "${PHP_INI_DIR}/conf.d/docker-php-ext-igbinary.ini"; \
    { \
    echo 'memory_limit=${PHP_MEMORY_LIMIT}'; \
    echo 'upload_max_filesize=${PHP_UPLOAD_LIMIT}'; \
    echo 'post_max_size=${PHP_UPLOAD_LIMIT}'; \
    } > "${PHP_INI_DIR}/conf.d/nextcloud.ini"; \
    mkdir -p /var/www/data; \
    mkdir -p /docker-entrypoint-hooks.d/pre-installation \
    /docker-entrypoint-hooks.d/post-installation \
    /docker-entrypoint-hooks.d/pre-upgrade \
    /docker-entrypoint-hooks.d/post-upgrade \
    /docker-entrypoint-hooks.d/before-starting; \
    chown -R www-data:root /var/www; \
    chmod -R g=u /var/www

VOLUME /var/www/html

COPY --from=common-tools /etc/ssl/certs/ca-certificates.crt /tmp/ca-bundle.crt
RUN if [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" != "cert-only" ]; then \
    mkdir -p /etc/ssl/certs && \
    cp /tmp/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt && \
    echo "CA bundle copied from common-tools"; \
    else \
    echo "Cert-only mode: Skipping internal CA bundle (using public CA from base image)"; \
    fi && \
    rm -f /tmp/ca-bundle.crt

COPY --chmod=755 --from=common-tools /usr/local/bin/nu /usr/local/bin/nu

COPY ./tls /tmp/tls-source/
COPY --chmod=755 ./scripts/tls/copy-tls.nu /tmp/copy-tls.nu

RUN if [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" = "ca-only" ]; then \
    echo "CA-only mode: CA bundle copied via COPY --from=common-tools, copy-tls.nu skipped" && \
    rm -rf /tmp/tls-source /tmp/copy-tls.nu || true; \
    elif [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" != "ca-only" ]; then \
    if [ ! -f /tmp/copy-tls.nu ]; then \
    echo "Error: copy-tls.nu not found. This should not happen for non-ca-only modes." && exit 1; \
    fi && \
    nu /tmp/copy-tls.nu \
    --enabled "'$TLS_ENABLED'" \
    --mode "'$TLS_MODE'" \
    --ca-name "'$TLS_CA_NAME'" \
    --cert-name "'$TLS_CERT_NAME'" \
    --source-certs /tmp/tls-source/certificates/ \
    --dest /tls/ && \
    rm -rf /tmp/tls-source /tmp/copy-tls.nu; \
    else \
    rm -rf /tmp/tls-source /tmp/copy-tls.nu || true; \
    fi

RUN mkdir -p /tls

# Configure Apache
RUN a2enmod headers rewrite remoteip ssl log_forensic; \
    { \
    echo 'RemoteIPHeader X-Real-IP'; \
    echo 'RemoteIPInternalProxy 10.0.0.0/8'; \
    echo 'RemoteIPInternalProxy 172.16.0.0/12'; \
    echo 'RemoteIPInternalProxy 192.168.0.0/16'; \
    } > /etc/apache2/conf-available/remoteip.conf; \
    a2enconf remoteip; \
    chown -R www-data:root /var/log/apache2; \
    chmod -R g=u /var/log/apache2

# Set Apache LimitRequestBody
RUN { \
    echo 'LimitRequestBody ${APACHE_BODY_LIMIT}'; \
    } > /etc/apache2/conf-available/apache-limits.conf; \
    a2enconf apache-limits

# Install Composer
RUN --mount=type=cache,id=nextcloud-composer-cache,target=/root/.composer/cache,sharing=locked \
    curl --silent --show-error https://getcomposer.org/installer -o /root/composer-setup.php && \
    php /root/composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
    rm /root/composer-setup.php

# Copy entrypoint scripts
COPY --chmod=755 ./scripts/entrypoint.sh /usr/bin/entrypoint.sh
COPY --chmod=755 ./scripts/entrypoint-init.nu /usr/bin/entrypoint-init.nu
RUN mkdir -p /usr/bin/lib

ENTRYPOINT ["/usr/bin/entrypoint.sh"]

CMD ["apache2-foreground"]
