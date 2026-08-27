ARG TMXY_GOSU_BUILDER_IMAGE=golang@sha256:6ef6e30f0ea5c384f6d111cf856e024e3086bbdcb1779da3f3b3fbba0aea53d2
ARG TMXY_POSTGRES_BASE_IMAGE=postgres@sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2
ARG SOURCE_DATE_EPOCH=1758654578

FROM ${TMXY_GOSU_BUILDER_IMAGE} AS gosu-builder

ARG SOURCE_DATE_EPOCH
ARG TMXY_GOSU_COMMIT=6456aaa0f3c854d199d0f037f068eb97515b7513
ARG TMXY_GOSU_SOURCE_SHA256=33d7537d588ea49458b9509bcf4554bdf5ceacc66da71e5caa1058ea3b689c3b

ADD --checksum=sha256:${TMXY_GOSU_SOURCE_SHA256} \
    https://github.com/tianon/gosu/archive/${TMXY_GOSU_COMMIT}.tar.gz \
    /tmp/gosu-source.tar.gz

RUN mkdir -p /src/gosu /out \
    && tar --extract --gzip --file /tmp/gosu-source.tar.gz \
      --strip-components=1 --directory /src/gosu \
    && cd /src/gosu \
    && test "$(git rev-parse HEAD 2>/dev/null || printf '%s' "${TMXY_GOSU_COMMIT}")" = "${TMXY_GOSU_COMMIT}" \
    && GOTOOLCHAIN=local CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
      go build -mod=readonly -trimpath -buildvcs=false \
      -ldflags='-s -w -buildid=' -o /out/gosu . \
    && /out/gosu --version | grep --fixed-strings \
      '1.19 (go1.26.7 on linux/amd64; gc)' \
    && touch --date="@${SOURCE_DATE_EPOCH}" /out/gosu

FROM ${TMXY_POSTGRES_BASE_IMAGE}

ARG SOURCE_DATE_EPOCH
ARG TMXY_GOSU_COMMIT=6456aaa0f3c854d199d0f037f068eb97515b7513

LABEL org.opencontainers.image.title="TMXY PostgreSQL runtime" \
      org.opencontainers.image.description="PostgreSQL 18.6 with gosu 1.19 rebuilt by the patched Go 1.26.7 toolchain" \
      org.opencontainers.image.version="18.6-gosu-go1.26.7" \
      org.opencontainers.image.base.name="postgres:18.6-alpine" \
      org.opencontainers.image.base.digest="sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2" \
      org.opencontainers.image.source="https://github.com/FaithandUnity/TMXY" \
      io.tmxy.gosu.source="https://github.com/tianon/gosu" \
      io.tmxy.gosu.revision="${TMXY_GOSU_COMMIT}" \
      io.tmxy.gosu.go-version="1.26.7" \
      io.tmxy.alpine.openssl-version="3.5.8-r0"

RUN --mount=type=bind,from=gosu-builder,source=/out,target=/tmp/gosu-build,ro \
    apk add --no-cache --upgrade libcrypto3=3.5.8-r0 libssl3=3.5.8-r0 \
    && cp /tmp/gosu-build/gosu /usr/local/bin/gosu \
    && chmod 0755 /usr/local/bin/gosu \
    && touch -d "@${SOURCE_DATE_EPOCH}" /usr/local/bin/gosu \
    && gosu --version | grep -F \
      '1.19 (go1.26.7 on linux/amd64; gc)' \
    && test "$(stat -c '%a' /usr/local/bin/gosu)" = '755'
