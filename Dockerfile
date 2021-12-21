FROM debian
ENV DEBIAN_FRONTEND=noninteractive
ARG TESTS
ARG SOURCE_COMMIT
ARG BUSYBOX_VERSION=1.34.1
ARG SUPERVISOR_VERSION=4.2.2

RUN dpkg --add-architecture armhf
RUN apt update && apt full-upgrade -y
RUN apt -y install apt-utils
RUN apt install -y \
    libsdl2-2.0-0 \
    libc6:armhf \
    libncurses5:armhf \
    libstdc++6:armhf \
    gcc-arm-linux-gnueabihf \
    git \
    make \
    cmake \
    python3 \
    python3-pip \
    python3-pkg-resources \
    curl \
    build-essential \
    golang \
    shellcheck \
    cron \
    iproute2 \
    libcurl4 \
    ca-certificates \
    procps \
    locales \
    unzip \
    zip \
    rsync \
    openssh-client \
    jq

WORKDIR /build
RUN git clone https://github.com/ptitSeb/box86
WORKDIR /build/box86/build
RUN cmake .. -DRPI4ARM64=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    && make -j4 \
    && make install

WORKDIR /build
RUN git clone https://github.com/ptitSeb/box64
WORKDIR /build/box64/build
RUN cmake .. -DRPI4ARM64=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    && make -j4 \
    && make install

WORKDIR /build/busybox
RUN curl -L -o /tmp/busybox.tar.bz2 https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2 \
    && tar xjvf /tmp/busybox.tar.bz2 --strip-components=1 -C /build/busybox \
    && make defconfig \
    && sed -i -e "s/^CONFIG_FEATURE_SYSLOGD_READ_BUFFER_SIZE=.*/CONFIG_FEATURE_SYSLOGD_READ_BUFFER_SIZE=2048/" .config \
    && make \
    && cp busybox /usr/local/bin/

WORKDIR /build/env2cfg
COPY ./env2cfg/ /build/env2cfg/
RUN if [ "${TESTS:-true}" = true ]; then \
        pip3 install tox \
        && tox \
        ; \
    fi
RUN python3 setup.py bdist --format=gztar

WORKDIR /build/valheim-logfilter
COPY ./valheim-logfilter/ /build/valheim-logfilter/
RUN go build -ldflags="-s -w" \
    && mv valheim-logfilter /usr/local/bin/

WORKDIR /build
RUN git clone https://github.com/Yepoleb/python-a2s.git \
    && cd python-a2s \
    && python3 setup.py bdist --format=gztar

WORKDIR /build/supervisor
RUN curl -L -o /tmp/supervisor.tar.gz https://github.com/Supervisor/supervisor/archive/${SUPERVISOR_VERSION}.tar.gz \
    && tar xzvf /tmp/supervisor.tar.gz --strip-components=1 -C /build/supervisor \
    && python3 setup.py bdist --format=gztar

COPY bootstrap /usr/local/sbin/
COPY valheim-status /usr/local/bin/
COPY valheim-is-idle /usr/local/bin/
COPY valheim-bootstrap /usr/local/bin/
COPY valheim-backup /usr/local/bin/
COPY valheim-updater /usr/local/bin/
COPY valheim-plus-updater /usr/local/bin/
COPY bepinex-updater /usr/local/bin/
COPY valheim-server /usr/local/bin/
COPY defaults /usr/local/etc/valheim/
COPY common /usr/local/etc/valheim/
COPY contrib/* /usr/local/share/valheim/contrib/
RUN chmod 755 /usr/local/sbin/bootstrap /usr/local/bin/valheim-*
RUN if [ "${TESTS:-true}" = true ]; then \
        shellcheck -a -x -s bash -e SC2034 \
            /usr/local/sbin/bootstrap \
            /usr/local/bin/valheim-backup \
            /usr/local/bin/valheim-is-idle \
            /usr/local/bin/valheim-bootstrap \
            /usr/local/bin/valheim-server \
            /usr/local/bin/valheim-updater \
            /usr/local/bin/valheim-plus-updater \
            /usr/local/bin/bepinex-updater \
            /usr/local/share/valheim/contrib/*.sh \
        ; \
    fi

WORKDIR /

RUN rm -rf /usr/local/lib/
RUN tar xzvf /build/supervisor/dist/supervisor-*.tar.gz
RUN tar xzvf /build/env2cfg/dist/env2cfg-*.tar.gz
RUN tar xzvf /build/python-a2s/dist/python-a2s-*.tar.gz
COPY supervisord.conf /usr/local/etc/supervisord.conf
RUN mkdir -p /usr/local/etc/supervisor/conf.d/ \
    && chmod 640 /usr/local/etc/supervisord.conf
RUN echo "${SOURCE_COMMIT:-unknown}" > /usr/local/etc/git-commit.HEAD

COPY fake-supervisord /usr/bin/supervisord

RUN groupadd -g "${PGID:-0}" -o valheim \
    && useradd -g "${PGID:-0}" -u "${PUID:-0}" -o --create-home valheim \
    && echo 'LANG="en_US.UTF-8"' > /etc/default/locale \
    && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && rm -f /bin/sh \
    && ln -s /bin/bash /bin/sh \
    && locale-gen \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3 1 \
    && apt-get clean \
    && mkdir -p /var/spool/cron/crontabs /var/log/supervisor /opt/valheim /opt/steamcmd /home/valheim/.config/unity3d/IronGate /config /var/run/valheim \
    && ln -s /config /home/valheim/.config/unity3d/IronGate/Valheim \
    && ln -s /usr/local/bin/busybox /usr/local/sbin/syslogd \
    && ln -s /usr/local/bin/busybox /usr/local/sbin/mkpasswd \
    && ln -s /usr/local/bin/busybox /usr/local/bin/vi \
    && ln -s /usr/local/bin/busybox /usr/local/bin/patch \
    && ln -s /usr/local/bin/busybox /usr/local/bin/unix2dos \
    && ln -s /usr/local/bin/busybox /usr/local/bin/dos2unix \
    && ln -s /usr/local/bin/busybox /usr/local/bin/makemime \
    && ln -s /usr/local/bin/busybox /usr/local/bin/xxd \
    && ln -s /usr/local/bin/busybox /usr/local/bin/wget \
    && ln -s /usr/local/bin/busybox /usr/local/bin/less \
    && ln -s /usr/local/bin/busybox /usr/local/bin/lsof \
    && ln -s /usr/local/bin/busybox /usr/local/bin/httpd \
    && ln -s /usr/local/bin/busybox /usr/local/bin/ssl_client \
    && ln -s /usr/local/bin/busybox /usr/local/bin/ip \
    && ln -s /usr/local/bin/busybox /usr/local/bin/ipcalc \
    && ln -s /usr/local/bin/busybox /usr/local/bin/ping \
    && ln -s /usr/local/bin/busybox /usr/local/bin/ping6 \
    && ln -s /usr/local/bin/busybox /usr/local/bin/iostat \
    && ln -s /usr/local/bin/busybox /usr/local/bin/setuidgid \
    && ln -s /usr/local/bin/busybox /usr/local/bin/ftpget \
    && ln -s /usr/local/bin/busybox /usr/local/bin/ftpput \
    && ln -s /usr/local/bin/busybox /usr/local/bin/bzip2 \
    && ln -s /usr/local/bin/busybox /usr/local/bin/xz \
    && ln -s /usr/local/bin/busybox /usr/local/bin/pstree \
    && ln -s /usr/local/bin/busybox /usr/local/bin/killall \
    && ln -s /usr/local/bin/busybox /usr/local/bin/bc \
    && curl -L -o /tmp/steamcmd_linux.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
    && tar xzvf /tmp/steamcmd_linux.tar.gz -C /opt/steamcmd/ \
    && chown valheim:valheim /var/run/valheim \
    && chown -R root:root /opt/steamcmd \
    && chmod 755 /opt/steamcmd/steamcmd.sh \
        /opt/steamcmd/linux32/steamcmd \
        /opt/steamcmd/linux32/steamerrorreporter \
        /usr/bin/supervisord \
    && cd "/opt/steamcmd" \
    && su - valheim -c "DEBUGGER=/usr/local/bin/box86 BOX86_DYNAREC=0 /opt/steamcmd/steamcmd.sh +login anonymous +quit" \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && date --utc --iso-8601=seconds > /usr/local/etc/build.date

EXPOSE 2456-2457/udp
EXPOSE 9001/tcp
EXPOSE 80/tcp
WORKDIR /
CMD ["/usr/local/sbin/bootstrap"]
