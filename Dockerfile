# Build app
# Deploy using Debian

ARG ELIXIR_VERSION=1.13.4
ARG OTP_VERSION=25.0.3
ARG NODE_VERSION=16.14.1
# ARG NODE_VERSION=lts

# ARG ELIXIR_DEBIAN_VERSION=buster-20210208
ARG ELIXIR_DEBIAN_VERSION=bullseye-20210902-slim

# https://docker.debian.net/
# https://hub.docker.com/_/debian
# ARG DEBIAN_VERSION=buster-slim
ARG DEBIAN_VERSION=bullseye-slim

# Use snapshot for consistent dependencies
# Needs to be updated manually
# See https://snapshot.debian.org/
ARG DEBIAN_SNAPSHOT=20220601

# Docker registry for internal images, e.g. 123.dkr.ecr.ap-northeast-1.amazonaws.com/
# If blank, docker.io will be used. If specified, should have a trailing slash.
ARG REGISTRY=""
# Registry for public images, e.g. debian, alpine, or postgres.
# Public images may be mirrored into the private registry, with e.g. Skopeo
ARG PUBLIC_REGISTRY=$REGISTRY

ARG BUILD_IMAGE_NAME=${PUBLIC_REGISTRY}hexpm/elixir
ARG BUILD_IMAGE_TAG=${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${ELIXIR_DEBIAN_VERSION}

ARG DEPLOY_IMAGE_NAME=${PUBLIC_REGISTRY}debian
ARG DEPLOY_IMAGE_TAG=$DEBIAN_VERSION

ARG INSTALL_IMAGE_NAME=$DEPLOY_IMAGE_NAME
ARG INSTALL_IMAGE_TAG=$DEPLOY_IMAGE_TAG

# App name, used to name directories
ARG APP_NAME=app

# Dir where app is installed
ARG APP_DIR=/app

# OS user for app to run under
# nonroot:x:65532:65532:nonroot:/home/nonroot:/usr/sbin/nologin
# nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
ARG APP_USER=nonroot
# OS group that app runs under
ARG APP_GROUP=$APP_USER
# OS numeric user and group id
ARG APP_USER_ID=65532
ARG APP_GROUP_ID=$APP_USER_ID

ARG LANG=C.UTF-8

# Trivy vulnerability scanner
# Fail for issues of severity = HIGH
# ARG TRIVY_OPTS="--exit-code 1 --severity HIGH"
# Fail for issues of severity = CRITICAL
ARG TRIVY_OPTS="--exit-code 1 --severity CRITICAL"
# Fail for any issues
# ARG TRIVY_OPTS="-d --exit-code 1"

# Elixir release env to build
ARG MIX_ENV=prod

# Name of Elixir release
ARG RELEASE=prod
# This should match mix.exs, e.g.
# defp releases do
#   [
#     prod: [
#       include_executables_for: [:unix],
#     ],
#   ]
# end

# App listen port
ARG APP_PORT=4001

# Create build base image with OS dependencies
FROM ${BUILD_IMAGE_NAME}:${BUILD_IMAGE_TAG} AS build-os-deps
    ARG DEBIAN_SNAPSHOT
    ARG LANG
    ENV LANG=$LANG

    ARG APP_USER
    ARG APP_GROUP
    ARG APP_USER_ID
    ARG APP_GROUP_ID

    # Create OS user and group to run app under
    RUN if ! grep -q "$APP_USER" /etc/passwd; \
        then groupadd -g "$APP_GROUP_ID" "$APP_GROUP" && \
        useradd -l -u "$APP_USER_ID" -g "$APP_GROUP" -s /usr/sbin/nologin "$APP_USER" && \
        rm /var/log/lastlog && rm /var/log/faillog; fi

    # Configure apt caching for use with BuildKit.
    # The default Debian Docker image has special apt config to clear caches,
    # but if we are using --mount=type=cache, then we want it.
    # https://github.com/debuerreotype/debuerreotype/blob/master/scripts/debuerreotype-minimizing-config
    RUN set -exu && \
        rm -f /etc/apt/apt.conf.d/docker-clean && \
        echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
        echo 'Acquire::CompressionTypes::Order:: "gz";' > /etc/apt/apt.conf.d/99use-gzip-compression

    RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
        --mount=type=cache,id=debconf,target=/var/cache/debconf,sharing=locked \
        set -exu && \
        apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get -y install -y -qq --no-install-recommends ca-certificates

    RUN set -exu && \
        echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bullseye main" > /etc/apt/sources.list && \
        echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT} bullseye-security main" >> /etc/apt/sources.list && \
        echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bullseye-updates main" >> /etc/apt/sources.list

    # Install tools and libraries to build binary libraries
    RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
        --mount=type=cache,id=debconf,target=/var/cache/debconf,sharing=locked \
        set -exu && \
        apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get -y install -y -qq --no-install-recommends \
            # Enable installation of packages over https
            apt-transport-https \
            build-essential \
            # Enable app to make outbound SSL calls.
            ca-certificates \
            curl \
            git \
            gnupg \
            gnupg-agent \
            jq \
            # software-properties-common \
            lsb-release \
            # Support ssl in container, as opposed to load balancer
            openssl \
            # Install default nodejs
            nodejs \
            # Install default Postgres
            # libpq-dev \
            # postgresql-client \
            && \
        # Install yarn
        curl -sL --ciphers ECDHE-RSA-AES128-GCM-SHA256 https://dl.yarnpkg.com/debian/pubkey.gpg -o /etc/apt/trusted.gpg.d/yarn.asc && \
        echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
        echo "Package: *\nPin: release o=dl.yarnpkg.com\nPin-Priority: 500\n" | tee /etc/apt/preferences.d/yarn.pref && \
        # Install Trivy
        curl -sL https://aquasecurity.github.io/trivy-repo/deb/public.key -o /etc/apt/trusted.gpg.d/trivy.asc && \
        printf "deb https://aquasecurity.github.io/trivy-repo/deb %s main" "$(lsb_release -sc)" | tee -a /etc/apt/sources.list.d/trivy.list && \
        apt-get update -qq && \
        apt-get -y install -y -qq --no-install-recommends yarn && \
        apt-get -y install -y -qq --no-install-recommends trivy && \
        curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin && \
        # https://www.networkworld.com/article/3453032/cleaning-up-with-apt-get.html
        # https://manpages.ubuntu.com/manpages/jammy/man8/apt-get.8.html
        # Remove packages installed temporarily. Removes everything related to
        # packages, including the configuration files, and packages
        # automatically installed because a package required them but, with the
        # other packages removed, are no longer needed.
        # apt-get purge -y --auto-remove curl && \
        # https://www.networkworld.com/article/3453032/cleaning-up-with-apt-get.html
        # https://manpages.ubuntu.com/manpages/jammy/man8/apt-get.8.html
        # Delete local repository of retrieved package files in /var/cache/apt/archives
        # This is handled automatically by /etc/apt/apt.conf.d/docker-clean
        # Use this if not running --mount=type=cache.
        # apt-get clean && \
        # Delete info on installed packages. This saves some space, but it can
        # be useful to have them as a record of what was installed, e.g. for auditing.
        # rm -rf /var/lib/dpkg && \
        # Delete debconf data files to save some space
        # rm -rf /var/cache/debconf && \
        # Delete index of available files from apt-get update
        # Use this if not running --mount=type=cache.
        # rm -rf /var/lib/apt/lists/*
        # Clear logs of installed packages
        truncate -s 0 /var/log/apt/* && \
        truncate -s 0 /var/log/dpkg.log

# Get Elixir deps
FROM build-os-deps AS build-deps-get
    ARG APP_DIR
    ENV HOME=$APP_DIR

    WORKDIR $APP_DIR

    # Copy only the minimum files needed for deps, improving caching
    COPY config ./config
    COPY mix.exs .
    COPY mix.lock .

    RUN mix 'do' local.rebar --force, local.hex --force
    RUN mix deps.get
    RUN mix esbuild.install

    RUN yarn add newman
    RUN yarn add snyk

# Create base image for tests
FROM build-deps-get AS test-image
    ARG APP_DIR

    ENV MIX_ENV=test

    WORKDIR $APP_DIR

    # Compile deps separately from app, improving Docker caching
    RUN mix deps.compile

    RUN mix dialyzer --plt

    # COPY coveralls.json ./
    COPY .credo.exs ./
    COPY .formatter.exs ./
    # COPY dialyzer-ignore ./

    # Non-umbrella
    COPY lib ./lib
    COPY priv ./priv
    COPY test ./test
    # COPY bin ./bin

    # Umbrella
    # COPY apps ./apps
    # COPY priv ./priv

    RUN mix compile --warnings-as-errors

    # For umbrella, using `mix cmd` ensures each app is compiled in
    # isolation https://github.com/elixir-lang/elixir/issues/9407
    #     mix cmd mix compile --warnings-as-errors


# Create Elixir release
FROM build-deps-get AS deploy-release
    ARG APP_DIR
    ARG RELEASE

    ENV MIX_ENV=prod

    WORKDIR $APP_DIR

    # This does a partial compile.
    # Doing "mix 'do' compile, assets.deploy" in a single stage is worse
    # because a single line of code changed causes a complete recompile.
    # With the stages separated most of the compilation is cached.

    # Compile deps separately from application for better caching
    RUN mix deps.compile

    # Compile assets the old way
    # WORKDIR /app/assets
    #
    # COPY assets/package.json assets/package-lock.json ./
    #
    # # Cache npm cache directory as type=cache
    # RUN --mount=type=cache,target=~/.npm,sharing=locked \
    #     npm --prefer-offline --no-audit --progress=false --loglevel=error ci
    #
    # COPY assets ./
    #
    # RUN --mount=type=cache,target=~/.npm,sharing=locked \
    #     npm run deploy
    #
    # Generate assets the really old way
    # RUN --mount=type=cache,target=~/.npm,sharing=locked \
    #   npm install && \
    #   node node_modules/webpack/bin/webpack.js --mode production

    # Install JavaScript deps using yarn
    # COPY assets/package.json assets/package.json
    # COPY assets/yarn.lock assets/yarn.lock
    # RUN yarn --cwd ./assets install --prod

    # Build JS and CS with esbuild
    COPY assets ./assets
    COPY priv ./priv

    RUN mix assets.deploy

    # Non-umbrella
    COPY lib ./lib

    # Umbrella
    # COPY apps ./apps

    RUN mix compile --warnings-as-errors

    # Build release
    COPY rel ./rel
    RUN mix release "$RELEASE"

# Create staging image for binaries which are copied into final deploy image
FROM ${INSTALL_IMAGE_NAME}:${INSTALL_IMAGE_TAG} AS deploy-install
    ARG DEBIAN_SNAPSHOT

    # Configure apt caching for use with BuildKit.
    # The default Debian Docker image has special config to clear caches.
    # If we are using --mount=type=cache, then we want it to preserve cached files.
    RUN set -exu && \
        rm -f /etc/apt/apt.conf.d/docker-clean && \
        echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
        echo 'Acquire::CompressionTypes::Order:: "gz";' > /etc/apt/apt.conf.d/99use-gzip-compression

    RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
        --mount=type=cache,id=debconf,target=/var/cache/debconf,sharing=locked \
        set -exu && \
        apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get -y install -y -qq --no-install-recommends ca-certificates

    RUN set -exu && \
        echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bullseye main" > /etc/apt/sources.list && \
        echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT} bullseye-security main" >> /etc/apt/sources.list && \
        echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bullseye-updates main" >> /etc/apt/sources.list

    RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
        --mount=type=cache,id=debconf,target=/var/cache/debconf,sharing=locked \
        set -exu && \
        apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get -y install -y -qq --no-install-recommends \
            # apt-transport-https \
            ca-certificates \
            curl \
            gnupg-agent \
            # software-properties-common \
            gnupg \
            unzip \
            lsb-release \
            locales \
            # Needed by Erlang VM
            libtinfo6 \
            && \
        curl -sL https://aquasecurity.github.io/trivy-repo/deb/public.key -o /etc/apt/trusted.gpg.d/trivy.asc && \
        printf "deb https://aquasecurity.github.io/trivy-repo/deb %s main" "$(lsb_release -sc)" | tee -a /etc/apt/sources.list.d/trivy.list && \
        apt-get update -qq && \
        apt-get -y install -y -qq --no-install-recommends trivy && \
        curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin && \
        # Generate locales specified in /etc/locale.gen
        locale-gen && \
        # Remove packages installed temporarily. Removes everything related to
        # packages, including the configuration files, and packages
        # automatically installed because a package required them but, with the
        # other packages removed, are no longer needed.
        # apt-get purge -y --auto-remove curl && \
        # https://www.networkworld.com/article/3453032/cleaning-up-with-apt-get.html
        # https://manpages.ubuntu.com/manpages/jammy/man8/apt-get.8.html
        # Delete local repository of retrieved package files in /var/cache/apt/archives
        # This is handled automatically by /etc/apt/apt.conf.d/docker-clean
        # Use this if not running --mount=type=cache.
        # apt-get clean && \
        # Delete info on installed packages. This saves some space, but it can
        # be useful to have them as a record of what was installed, e.g. for auditing.
        # rm -rf /var/lib/dpkg && \
        # Delete debconf data files to save some space
        # rm -rf /var/cache/debconf && \
        # Delete index of available files from apt-get update
        # Use this if not running --mount=type=cache.
        # rm -rf /var/lib/apt/lists/*
        # Clear logs of installed packages
        truncate -s 0 /var/log/apt/* && \
        truncate -s 0 /var/log/dpkg.log

# Create base image for deploy, with everything but the code release
FROM ${DEPLOY_IMAGE_NAME}:${DEPLOY_IMAGE_TAG} AS deploy-base
    ARG DEBIAN_SNAPSHOT
    ARG LANG
    ARG APP_USER
    ARG APP_GROUP
    ARG APP_USER_ID
    ARG APP_GROUP_ID

    ARG MIX_ENV=prod
    ARG RELEASE

    # COPY --from=deploy-install /usr/lib/locale/C.UTF-8 /usr/lib/locale/C.UTF-8

    ENV LANG=$LANG

    # Create OS user and group to run app under
    RUN if ! grep -q "$APP_USER" /etc/passwd; \
        then groupadd -g "$APP_GROUP_ID" "$APP_GROUP" && \
        useradd -l -u "$APP_USER_ID" -g "$APP_GROUP" -s /usr/sbin/nologin "$APP_USER" && \
        rm /var/log/lastlog && rm /var/log/faillog; fi

    # Configure apt caching for use with BuildKit.
    # The default Debian Docker image has special config to clear caches.
    # If we are using --mount=type=cache, then we want it to preserve cached files.
    RUN set -exu && \
        rm -f /etc/apt/apt.conf.d/docker-clean && \
        echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
        echo 'Acquire::CompressionTypes::Order:: "gz";' > /etc/apt/apt.conf.d/99use-gzip-compression

    RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
        --mount=type=cache,id=debconf,target=/var/cache/debconf,sharing=locked \
        set -exu && \
        apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get -y install -y -qq --no-install-recommends ca-certificates

    RUN set -exu && \
        echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bullseye main" > /etc/apt/sources.list && \
        echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT} bullseye-security main" >> /etc/apt/sources.list && \
        echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bullseye-updates main" >> /etc/apt/sources.list

    # If LANG=C.UTF-8 is not enough, build full featured locale
    # RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    #     --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
    #     set -exu && \
    #       apt-get update -qq && \
    #       DEBIAN_FRONTEND=noninteractive \
    #       apt-get -y install -y -qq --no-install-recommends locales && \
    #       localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
    #
    # ENV LANG en_US.utf8

    RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
        --mount=type=cache,id=debconf,target=/var/cache/debconf,sharing=locked \
        set -exu && \
        apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get -y install -y -qq --no-install-recommends \
            # Enable installation of packages over https
            # apt-transport-https \
            # Enable the app to make outbound SSL calls.
            ca-certificates \
            # Allow app to listen on HTTPS. May not be needed if handled
            # outside the application, e.g. in load balancer.
            openssl \
            # tini is a minimal init which will reap zombie processes
            # https://github.com/krallin/tini
            # tini \
            # bind-utils \
            # Needed by Erlang VM
            libtinfo6 \
        && \
        # Remove packages installed temporarily. Removes everything related to
        # packages, including the configuration files, and packages
        # automatically installed because a package required them but, with the
        # other packages removed, are no longer needed.
        # apt-get purge -y --auto-remove curl && \
        # https://www.networkworld.com/article/3453032/cleaning-up-with-apt-get.html
        # https://manpages.ubuntu.com/manpages/jammy/man8/apt-get.8.html
        # Delete local repository of retrieved package files in /var/cache/apt/archives
        # This is handled automatically by /etc/apt/apt.conf.d/docker-clean
        # Use this if not running --mount=type=cache.
        # apt-get clean && \
        # Delete info on installed packages. This saves some space, but it can
        # be useful to have them as a record of what was installed, e.g. for auditing.
        # rm -rf /var/lib/dpkg && \
        # Delete debconf data files to save some space
        # rm -rf /var/cache/debconf && \
        # Delete index of available files from apt-get update
        # Use this if not running --mount=type=cache.
        # rm -rf /var/lib/apt/lists/*
        # Clear logs of installed packages
        truncate -s 0 /var/log/apt/* && \
        truncate -s 0 /var/log/dpkg.log

# Create deploy image with vulnerability scanners
FROM deploy-base AS deploy-scan
    # ARG TRIVY_OPTS
    # COPY --from=deploy-install /usr/local/bin/trivy /usr/local/bin/trivy
    # COPY --from=deploy-install /usr/local/share/trivy/templates /usr/local/share/trivy/templates
    # COPY --from=deploy-install /usr/local/bin/grype /usr/local/bin/grype
    COPY --from=test-image /usr/local/bin/trivy /usr/local/bin/trivy
    COPY --from=test-image /usr/local/share/trivy/templates /usr/local/share/trivy/templates
    COPY --from=test-image /usr/local/bin/grype /usr/local/bin/grype

    # RUN set -exu && \
    #     mkdir -p /sarif-reports && \
    #     # Succeed for issues of severity = HIGH
    #     # trivy filesystem $TRIVY_OPTS --format sarif -o /sarif-reports/trivy.high.sarif --exit-code 0 --severity HIGH --no-progress / && \
    #     trivy filesystem $TRIVY_OPTS --exit-code 0 --severity HIGH --no-progress / && \
    #     # Fail for issues of severity = CRITICAL
    #     # trivy filesystem $TRIVY_OPTS --format sarif -o /sarif-reports/trivy.sarif --exit-code 1 --severity CRITICAL --no-progress /
    #     # Fail for any issues
    #     # trivy filesystem -d --exit-code 1 --no-progress /
    #     trivy filesystem --format sarif -o /sarif-reports/trivy.sarif --no-progress $TRIVY_OPTS --no-progress /

# Create final app image which gets deployed
FROM deploy-base AS deploy
    ARG APP_DIR
    ARG APP_NAME
    ARG APP_USER
    ARG APP_GROUP
    ARG APP_PORT

    ARG MIX_ENV=prod
    ARG RELEASE

    # Set environment vars used by the app
    # SECRET_KEY_BASE and DATABASE_URL env vars should be set when running the application
    # Maybe set COOKIE and other things
    ENV HOME=$APP_DIR \
        PORT=$APP_PORT \
        PHX_SERVER=true \
        RELEASE=$RELEASE \
        # Writable tmp directory for releases
        RELEASE_TMP="/run/${APP_NAME}"

    RUN set -exu && \
        # Create app dirs
        mkdir -p "/run/${APP_NAME}" && \
        # Make dirs writable by app
        chown -R "${APP_USER}:${APP_GROUP}" \
            # Needed for RELEASE_TMP
            "/run/${APP_NAME}"

    # USER $APP_USER

    # Setting WORKDIR after USER makes directory be owned by the user.
    # Setting it before makes it owned by root, which is more secure.
    WORKDIR $APP_DIR

    # When using a startup script, copy to /app/bin
    # COPY bin ./bin

    USER $APP_USER

    # Chown files while copying. Running "RUN chown -R app:app /app"
    # adds an extra layer which is about 10Mb, a huge difference if the
    # app image is around 20Mb.

    # TODO: For more security, change specific files to have group read/execute
    # permissions while leaving them owned by root

    # When using a startup script, unpack release under "/app/current" dir
    # WORKDIR $APP_DIR/current

    COPY --from=deploy-release --chown="$APP_USER:$APP_GROUP" "/app/_build/${MIX_ENV}/rel/${RELEASE}" ./

    EXPOSE $APP_PORT

    # "bin" is the directory under the unpacked release, and "prod" is the name
    # of the release top level script, which should match the RELEASE var.
    ENTRYPOINT ["bin/prod"]

    # Run under init to avoid zombie processes
    # https://github.com/krallin/tini
    # ENTRYPOINT ["/sbin/tini", "--", "bin/prod"]

    # Wrapper script which runs e.g. migrations before starting
    # ENTRYPOINT ["bin/start-docker"]

    # Run app in foreground
    CMD ["start"]

# Dev image which mounts code from local filesystem
FROM build-os-deps AS dev
    ARG LANG
    ARG APP_NAME
    ARG APP_DIR
    ARG APP_USER
    ARG APP_GROUP
    ARG APP_PORT

    ARG MIX_ENV

    # Set environment vars used by the app
    ENV LANG=$LANG \
        HOME=$APP_DIR \
        PORT=$APP_PORT \
        PHX_SERVER=true

    RUN set -exu && \
        # Create app dirs
        mkdir -p "/run/${APP_NAME}" && \
        # Make dirs writable by app
        chown -R "${APP_USER}:${APP_GROUP}" \
            # Needed for RELEASE_TMP
            "/run/${APP_NAME}"

    RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
        --mount=type=cache,id=debconf,target=/var/cache/debconf,sharing=locked \
        set -exu && \
        apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get -y install -y -qq --no-install-recommends \
            inotify-tools \
            ssh \
            sudo \
        && \
        # https://www.networkworld.com/article/3453032/cleaning-up-with-apt-get.html
        # https://manpages.ubuntu.com/manpages/jammy/man8/apt-get.8.html
        # Remove packages installed temporarily. Removes everything related to
        # packages, including the configuration files, and packages
        # automatically installed because a package required them but, with the
        # other packages removed, are no longer needed.
        # apt-get purge -y --auto-remove curl && \
        # Delete local repository of retrieved package files in /var/cache/apt/archives
        # This is handled automatically by /etc/apt/apt.conf.d/docker-clean
        # Use this if not running --mount=type=cache.
        # apt-get clean && \
        # Delete info on installed packages. This saves some space, but it can
        # be useful to have them as a record of what was installed, e.g. for auditing.
        # rm -rf /var/lib/dpkg && \
        # Delete debconf data files to save some space
        # rm -rf /var/cache/debconf && \
        # Delete index of available files from apt-get update
        # Use this if not running --mount=type=cache.
        # rm -rf /var/lib/apt/lists/*
        # Clear logs of installed packages
        truncate -s 0 /var/log/apt/* && \
        truncate -s 0 /var/log/dpkg.log

    USER $APP_USER

    WORKDIR $APP_DIR

    RUN mix 'do' local.rebar --force, local.hex --force

    # RUN mix esbuild.install

    # Instead of copying sources, could use bind mount, e.g.
    # RUN --mount=target=.
    # see https://adoptingerlang.org/docs/production/docker/#efficient-caching

    EXPOSE $APP_PORT

    CMD [ "sleep", "infinity" ]

# Copy build artifacts to host
FROM scratch AS artifacts
    ARG MIX_ENV
    ARG RELEASE

    COPY --from=deploy-release "/app/_build/${MIX_ENV}/rel/${RELEASE}" /release
    COPY --from=deploy-release /app/priv/static /static

# Default target
FROM deploy
