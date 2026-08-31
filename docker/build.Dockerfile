FROM debian:trixie-slim

ARG NODE_VERSION="24"

# set GO related paths under /tmp to avoid ownerhip/permission issues in Github CI build
ENV GOPATH=/tmp/go
ENV GOCACHE=/tmp/go-build-cache

# set deb to non-interactive mode and upgrade packages
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && export DEBIAN_FRONTEND=noninteractive
RUN apt-get -y update && apt-get -y upgrade

# install latest nodejs lts version
RUN apt-get -y update && apt-get install -y apt-transport-https ca-certificates curl gnupg &&\
  curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
RUN apt-get -y update && apt-get -y install nodejs && npm update -g npm

# install all needed (or wanted) distro packages
# golang: dawn/tint generates real production sources with a Go program. gclient
# would supply that toolchain as a cipd dep of dawn's own DEPS, which a source
# tarball doesn't carry - see provide_dawn_go() in scripts/shared.sh.
# xdg-utils: xdg-mime/xdg-settings are vendored into out/Default at package time.
# clang-format: symlinked into buildtools/linux64-format, which src/DEPS would
# have pulled from GCS. Chromium 152 generates crubit's support headers through
# it, so without it ninja rejects the graph before compiling anything.
# clang/cmake/lld: only a non-x86_64 *host* compiles LLVM itself (there is no
# prebuilt non-x86 clang/rust for Linux - see setup_toolchain() in
# scripts/shared.sh). tools/clang/scripts/build.py always configures with
# -DLLVM_ENABLE_LLD=ON, which makes LLVM's cmake feed -fuse-ld=lld to the host
# compiler we pass as --host-cc/--host-cxx and hard-fail configure when it does
# not work; Debian's clang package does not pull lld in on its own.
RUN apt-get -y install bison clang clang-format cmake debhelper desktop-file-utils flex git golang gperf gsettings-desktop-schemas-dev\
  imagemagick libasound2-dev libavcodec-dev libavformat-dev libavutil-dev libcap-dev libcups2-dev libcurl4-openssl-dev\ 
  libdrm-dev libegl1-mesa-dev libelf-dev libevent-dev libexif-dev libflac-dev libgbm-dev libgcrypt20-dev libgl1-mesa-dev\
  libgles2-mesa-dev libglew-dev libglib2.0-dev libglu1-mesa-dev libgtk-3-dev libhunspell-dev libjpeg-dev libjs-jquery-flot\
  libjsoncpp-dev libkrb5-dev liblcms2-dev libminizip-dev libmodpbase64-dev libnspr4-dev libnss3-dev libopenjp2-7-dev\
  libopus-dev libpam0g-dev libpci-dev libpipewire-0.3-dev libpng-dev libpulse-dev libre2-dev libsnappy-dev libspeechd-dev\
  libudev-dev libusb-1.0-0-dev libva-dev libvpx-dev libwebp-dev libx11-xcb-dev libxcb-dri3-dev libxshmfence-dev libxslt1-dev\
  libxss-dev libxt-dev libxtst-dev lld mesa-common-dev ninja-build pkg-config python3-httplib2 python3-jinja2 python3-pyparsing\
  python3-setuptools python3-six python3-xcbgen python-is-python3 qtbase5-dev rsync sudo uuid-dev valgrind vim wdiff x11-apps\
  xcb-proto xdg-utils xfonts-base xvfb xz-utils yasm

# create builder user
RUN groupadd -g 1000 builder && useradd -d /home/builder -g 1000 -u 1000 -m builder
# switch to builder user
USER builder
# copy config file for gsclient depot tools
COPY --chmod=777 --chown=builder:builder metrics.cfg /home/builder/.config/depot_tools/

WORKDIR /repo

