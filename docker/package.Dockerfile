FROM debian:trixie-slim

## Set deb to non-interactive mode and upgrade packages
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && export DEBIAN_FRONTEND=noninteractive
RUN apt -y update && apt -y upgrade

## Install system dependencies
RUN apt -y install binutils desktop-file-utils dpkg file imagemagick wget xz-utils pv curl jq zsync

# Downloaded from the release's own URL rather than looked up through
# api.github.com. The old form asked the API for the asset list and piped it
# through jq, which made the packaging image depend on an unauthenticated API
# call from inside a Docker build - and that call is rate-limited. Run 61's
# arm64 package job died on exactly that: the API returned a body with no
# .assets, so jq said "Cannot iterate over null (null)" and the build stopped
# with exit 123. `curl -s` had swallowed the real 403, so the log never showed
# the cause, only the symptom.
#
# The tag was already pinned at 1.9.0, so the asset URL was fixed all along
# and the lookup bought nothing. -f makes a failed download fail here, with a
# status, instead of writing an error page to the target and failing later.
# The sha256 check below is unchanged and remains the real authority on what
# was fetched; both URLs were verified to hash to the values it already lists.
RUN curl -fLo /usr/bin/appimagetool-$(uname -m).AppImage \
    https://github.com/AppImage/appimagetool/releases/download/1.9.0/appimagetool-$(uname -m).AppImage

RUN cat <<EOF | (cd /usr/bin; sha256sum -c --strict --ignore-missing)
    46fdd785094c7f6e545b61afcfb0f3d98d8eab243f644b4b17698c01d06083d1  appimagetool-x86_64.AppImage
    04f45ea45b5aa07bb2b071aed9dbf7a5185d3953b11b47358c1311f11ea94a96  appimagetool-aarch64.AppImage
    2148af7e848c8f1f8b079045907828874fc14ec7f593426b6d0a95c759174de4  appimagetool-i686.AppImage
    848f3bcccc7e08da1414156e78a59da76fcb5a8c98d3d4e9ef8ab557e5892ad5  appimagetool-armhf.AppImage
EOF

RUN mv /usr/bin/appimagetool-$(uname -m).AppImage /usr/bin/appimagetool

RUN chmod +x /usr/bin/appimagetool

# create builder user
RUN groupadd -g 1000 builder && useradd -d /home/builder -g 1000 -u 1000 -m builder

USER builder

## Create and set WORKDIR to mount in docker build
WORKDIR /repo
