ARG TMXY_BASE_IMAGE=debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
FROM ${TMXY_BASE_IMAGE}

ARG DEBIAN_SNAPSHOT=20260824T000000Z
ARG LLVM_REVISION=1:21.1.8~++20251221032947+2078da43e25a-1~exp1~20251221153113.67
ARG LLVM_ASC_SHA256=8b2a587ffd672c4687e7581dad4b2f6c1bb2ad6b480cd9771ba2ff48e0b8c75d
ARG LLVM_KEYRING_SHA256=99f4985fd25cdf4c15b07fd6139d5e205cbd39bab1c65d83484efc92a1d67344
ARG CMAKE_VERSION=4.4.2
ARG CMAKE_ARCHIVE_SHA256=3ada9a3f5d8a85413579bdd0ea6aa8e8da86efdd6d15c91a1afa517f2021956c

LABEL org.opencontainers.image.title="TMXY backend toolchain" \
      org.opencontainers.image.description="Locked Linux amd64 C++20 builder for TMXY Rebuild" \
      org.opencontainers.image.version="p0-08" \
      org.opencontainers.image.base.name="debian:bookworm-slim" \
      org.opencontainers.image.base.digest="sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171"

RUN printf '%s\n' \
      'Types: deb' \
      "URIs: http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}" \
      'Suites: bookworm bookworm-updates' \
      'Components: main' \
      'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
      'Check-Valid-Until: no' \
      '' \
      'Types: deb' \
      "URIs: http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}" \
      'Suites: bookworm-security' \
      'Components: main' \
      'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
      'Check-Valid-Until: no' \
      > /etc/apt/sources.list.d/debian.sources \
    && apt-get -o Acquire::Retries=5 -o Acquire::ForceIPv4=true update \
    && apt-get -o Acquire::Retries=5 -o Acquire::ForceIPv4=true install -y --no-install-recommends \
      build-essential=12.9 \
      ca-certificates=20250419~deb12u1 \
      curl=7.88.1-10+deb12u15 \
      git=1:2.39.5-0+deb12u3 \
      gnupg=2.2.40-1.1+deb12u2 \
      ninja-build=1.11.1-2~deb12u1 \
      pkg-config=1.8.1-1 \
      python3=3.11.2-1+b1 \
      python3-pip-whl=23.0.1+dfsg-1 \
      python3-setuptools-whl=66.1.1-1+deb12u2 \
      python3-venv=3.11.2-1+b1 \
      python3.11-venv=3.11.2-6+deb12u8 \
      xz-utils=5.4.1-1+deb12u1 \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --silent --show-error --location \
      https://apt.llvm.org/llvm-snapshot.gpg.key -o /tmp/llvm-snapshot.gpg.key \
    && printf '%s  %s\n' "${LLVM_ASC_SHA256}" /tmp/llvm-snapshot.gpg.key | sha256sum --check --strict \
    && gpg --batch --dearmor --output /usr/share/keyrings/llvm-snapshot.gpg /tmp/llvm-snapshot.gpg.key \
    && printf '%s  %s\n' "${LLVM_KEYRING_SHA256}" /usr/share/keyrings/llvm-snapshot.gpg | sha256sum --check --strict \
    && printf '%s\n' \
      'deb [signed-by=/usr/share/keyrings/llvm-snapshot.gpg] https://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-21 main' \
      > /etc/apt/sources.list.d/llvm-toolchain.list \
    && apt-get -o Acquire::Retries=5 -o Acquire::ForceIPv4=true update \
    && apt-get -o Acquire::Retries=5 -o Acquire::ForceIPv4=true install -y --no-install-recommends \
      clang-21="${LLVM_REVISION}" \
      clang-format-21="${LLVM_REVISION}" \
      clang-tidy-21="${LLVM_REVISION}" \
      lld-21="${LLVM_REVISION}" \
    && rm -rf /var/lib/apt/lists/* /tmp/llvm-snapshot.gpg.key

RUN mkdir -p /opt/cmake \
    && curl --fail --silent --show-error --location \
      "https://cmake.org/files/v4.4/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" \
      -o /tmp/cmake.tar.gz \
    && printf '%s  %s\n' "${CMAKE_ARCHIVE_SHA256}" /tmp/cmake.tar.gz | sha256sum --check --strict \
    && tar --extract --gzip --file /tmp/cmake.tar.gz --strip-components=1 --directory /opt/cmake \
    && rm /tmp/cmake.tar.gz

COPY conan-requirements.txt /tmp/conan-requirements.txt
RUN python3 -m venv /opt/conan \
    && /opt/conan/bin/pip install --disable-pip-version-check --no-cache-dir \
      --require-hashes --requirement /tmp/conan-requirements.txt \
    && rm /tmp/conan-requirements.txt

RUN groupadd --gid 10001 tmxy \
    && useradd --uid 10001 --gid tmxy --create-home --shell /bin/sh tmxy

ENV PATH="/opt/cmake/bin:/opt/conan/bin:${PATH}" \
    CC=clang-21 \
    CXX=clang++-21 \
    CONAN_HOME=/home/tmxy/.conan2 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

USER tmxy
WORKDIR /workspace

CMD ["clang++-21", "--version"]
