#!/bin/bash -e

# This scrip is for building AppImage
# Please run this scrip in docker image: ubuntu:18.04
# E.g: docker run --rm -v `git rev-parse --show-toplevel`:/build ubuntu:18.04 /build/.github/workflows/build_appimage.sh
# If you need keep store build cache in docker volume, just like:
#   $ docker volume create qbee-cache
#   $ docker run --rm -v `git rev-parse --show-toplevel`:/build -v qbee-cache:/var/cache/apt -v qbee-cache:/usr/src ubuntu:18.04 /build/.github/workflows/build_appimage.sh
# Artifacts will copy to the same directory.

set -o pipefail


# match qt version prefix. E.g 5 --> 5.15.2, 5.12 --> 5.12.10
export QT_VER_PREFIX="6"
export LIBTORRENT_BRANCH="RC_1_2"

rm -f /etc/apt/sources.list.d/*.list*
# Ubuntu mirror for local building
if [ x"${USE_CHINA_MIRROR}" = x1 ]; then
  source /etc/os-release
  cat >/etc/apt/sources.list <<EOF
deb http://repo.huaweicloud.com/ubuntu/ ${UBUNTU_CODENAME} main restricted universe multiverse
deb http://repo.huaweicloud.com/ubuntu/ ${UBUNTU_CODENAME}-updates main restricted universe multiverse
deb http://repo.huaweicloud.com/ubuntu/ ${UBUNTU_CODENAME}-backports main restricted universe multiverse
deb http://repo.huaweicloud.com/ubuntu/ ${UBUNTU_CODENAME}-security main restricted universe multiverse
EOF
  export PIP_INDEX_URL="https://repo.huaweicloud.com/repository/pypi/simple"
fi

export DEBIAN_FRONTEND=noninteractive

# keep debs in container for store cache in docker volume
rm -f /etc/apt/apt.conf.d/*
echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' >/etc/apt/apt.conf.d/01keep-debs
echo -e 'Acquire::https::Verify-Peer "false";\nAcquire::https::Verify-Host "false";' >/etc/apt/apt.conf.d/99-trust-https

# Since cmake 3.23.0 CMAKE_INSTALL_LIBDIR will force set to lib/<multiarch-tuple> on Debian
echo '/usr/local/lib/x86_64-linux-gnu' >/etc/ld.so.conf.d/x86_64-linux-gnu-local.conf

apt update
apt install -y software-properties-common apt-transport-https

add-apt-repository ppa:ubuntu-toolchain-r/test

if [ x"${USE_CHINA_MIRROR}" = x1 ]; then
  sed -i 's@http://ppa.launchpad.net@https://launchpad.proxy.ustclug.org@' /etc/apt/sources.list.d/*.list
fi

apt update
apt install -y \
  curl \
  git \
  unzip \
  pkg-config \
  libssl-dev \
  libzstd-dev \
  zlib1g-dev \
  libbrotli-dev \
  libdouble-conversion-dev \
  libgraphite2-dev \
  libsystemd-dev \
  libxcb1-dev \
  libicu-dev \
  libgtk2.0-dev \
  build-essential \
  libgl1-mesa-dev \
  libfontconfig1-dev \
  libfreetype6-dev \
  libx11-dev \
  libx11-xcb-dev \
  libxext-dev \
  libxfixes-dev \
  libxi-dev \
  libxrender-dev \
  libxcb1-dev \
  libxcb-keysyms1-dev \
  libxcb-image0-dev \
  libxcb-shm0-dev \
  libxcb-icccm4-dev \
  libxcb-sync-dev \
  libxcb-xfixes0-dev \
  libxcb-shape0-dev \
  libxcb-randr0-dev \
  libxcb-render-util0-dev \
  libxcb-util-dev \
  libxcb-xinerama0-dev \
  libxcb-xkb-dev \
  libxkbcommon-dev \
  libxkbcommon-x11-dev \
  gcc-11 \
  g++-11

#  libwayland-dev \
#  libwayland-egl-backend-dev \

apt autoremove --purge -y
# make gcc-8 as default gcc
update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 800 --slave /usr/bin/g++ g++ /usr/bin/g++-11
# strip all compiled files by default
export CFLAGS='-s'
export CXXFLAGS='-s'
# Force refresh ld.so.cache
ldconfig
SELF_DIR="$(dirname "$(readlink -f "${0}")")"
echo $SELF_DIR

retry() {
  # max retry 5 times
  try=5
  # sleep 3s every retry
  sleep_time=3
  for i in $(seq ${try}); do
    echo "executing with retry: $@" >&2
    if eval "$@"; then
      return 0
    else
      echo "execute '$@' failed, tries: ${i}" >&2
      sleep ${sleep_time}
    fi
  done
  echo "execute '$@' failed" >&2
  return 1
}

# join array to string. E.g join_by ',' "${arr[@]}"
join_by() {
  local separator="$1"
  shift
  local first="$1"
  shift
  printf "%s" "$first" "${@/#/$separator}"
}



# install cmake and ninja-build
if ! which cmake &>/dev/null; then
  cmake_latest_ver="$(retry curl -ksSL --compressed https://cmake.org/download/ \| grep "'Latest Release'" \| sed -r "'s/.*Latest Release\s*\((.+)\).*/\1/'" \| head -1)"
  cmake_binary_url="https://github.com/Kitware/CMake/releases/download/v${cmake_latest_ver}/cmake-${cmake_latest_ver}-linux-x86_64.tar.gz"
  cmake_sha256_url="https://github.com/Kitware/CMake/releases/download/v${cmake_latest_ver}/cmake-${cmake_latest_ver}-SHA-256.txt"
  if [ x"${USE_CHINA_MIRROR}" = x1 ]; then
    cmake_binary_url="https://ghproxy.com/${cmake_binary_url}"
    cmake_sha256_url="https://ghproxy.com/${cmake_sha256_url}"
  fi
  if [ -f "/usr/src/cmake-${cmake_latest_ver}-linux-x86_64.tar.gz" ]; then
    cd /usr/src
    if ! retry curl -ksSL --compressed "${cmake_sha256_url}" \| grep "cmake-${cmake_latest_ver}-linux-x86_64.tar.gz" \| sha256sum -c; then
      rm -f "/usr/src/cmake-${cmake_latest_ver}-linux-x86_64.tar.gz"
    fi
  fi
  if [ ! -f "/usr/src/cmake-${cmake_latest_ver}-linux-x86_64.tar.gz" ]; then
    retry curl -kLo "/usr/src/cmake-${cmake_latest_ver}-linux-x86_64.tar.gz" "${cmake_binary_url}"
  fi
  tar -zxf "/usr/src/cmake-${cmake_latest_ver}-linux-x86_64.tar.gz" -C /usr/local --strip-components 1
fi
cmake --version
if ! which ninja &>/dev/null; then
  ninja_ver="$(retry curl -ksSL --compressed https://ninja-build.org/ \| grep "'The last Ninja release is'" \| sed -r "'s@.*<b>(.+)</b>.*@\1@'" \| head -1)"
  ninja_binary_url="https://github.com/ninja-build/ninja/releases/download/${ninja_ver}/ninja-linux.zip"
  if [ x"${USE_CHINA_MIRROR}" = x1 ]; then
    ninja_binary_url="https://ghproxy.com/${ninja_binary_url}"
  fi
  if [ ! -f "/usr/src/ninja-${ninja_ver}-linux.zip.download_ok" ]; then
    rm -f "/usr/src/ninja-${ninja_ver}-linux.zip"
    retry curl -kLC- -o "/usr/src/ninja-${ninja_ver}-linux.zip" "${ninja_binary_url}"
    touch "/usr/src/ninja-${ninja_ver}-linux.zip.download_ok"
  fi
  unzip -d /usr/local/bin "/usr/src/ninja-${ninja_ver}-linux.zip"
fi
echo "Ninja version $(ninja --version)"

# install qt
qt_major_ver="$(retry curl -ksSL --compressed https://download.qt.io/official_releases/qt/ \| sed -nr "'s@.*href=\"([0-9]+(\.[0-9]+)*)/\".*@\1@p'" \| grep \"^${QT_VER_PREFIX}\" \| head -1)"
if [ -z "$qt_ver" ]; then
  qt_ver="$(retry curl -ksSL --compressed https://download.qt.io/official_releases/qt/${qt_major_ver}/ \| sed -nr "'s@.*href=\"([0-9]+(\.[0-9]+)*)/\".*@\1@p'" \| grep \"^${QT_VER_PREFIX}\" \| head -1)"
fi
echo "Using qt version: ${qt_ver}"
mkdir -p "/usr/src/qtbase-${qt_ver}" \
  "/usr/src/qttools-${qt_ver}" \
  "/usr/src/qtsvg-${qt_ver}" \
  "/usr/src/qtwayland-${qt_ver}"
if [ ! -f "/usr/src/qtbase-${qt_ver}/.unpack_ok" ]; then
  qtbase_url="https://download.qt.io/official_releases/qt/${qt_major_ver}/${qt_ver}/submodules/qtbase-everywhere-src-${qt_ver}.tar.xz"
  retry curl -kSL --compressed "${qtbase_url}" \| tar Jxf - -C "/usr/src/qtbase-${qt_ver}" --strip-components 1
  touch "/usr/src/qtbase-${qt_ver}/.unpack_ok"
fi
cd "/usr/src/qtbase-${qt_ver}"
rm -fr CMakeCache.txt CMakeFiles
#  -ltcg \
#  -optimize-size \
#  -openssl-linked \
#  -qt-libjpeg \
#  -qt-libpng \
#  -qt-pcre \
#  -qt-harfbuzz \
#  -no-icu \
#  -no-directfb \
#  -no-linuxfb \
#  -no-eglfs \
#  -no-feature-testlib \
#  -no-feature-vnc \
#  -feature-optimize_full \
./configure \
  -ltcg \
  -openssl-linked \
  -qt-libjpeg \
  -qt-libpng \
  -qt-pcre \
  -qt-harfbuzz \
  -release \
  -static \
  -c++std c++17 \
  -feature-optimize_full \
  -skip wayland \
  -no-directfb \
  -no-linuxfb \
  -no-eglfs \
  -no-feature-testlib \
  -no-feature-vnc \
  -nomake examples \
  -nomake tests
cmake --build . --parallel
cmake --install .
export QT_BASE_DIR="$(ls -rd /usr/local/Qt-* | head -1)"
export LD_LIBRARY_PATH="${QT_BASE_DIR}/lib:${LD_LIBRARY_PATH}"
export PATH="${QT_BASE_DIR}/bin:${PATH}"
if [ ! -f "/usr/src/qtsvg-${qt_ver}/.unpack_ok" ]; then
  qtsvg_url="https://download.qt.io/official_releases/qt/${qt_major_ver}/${qt_ver}/submodules/qtsvg-everywhere-src-${qt_ver}.tar.xz"
  retry curl -kSL --compressed "${qtsvg_url}" \| tar Jxf - -C "/usr/src/qtsvg-${qt_ver}" --strip-components 1
  touch "/usr/src/qtsvg-${qt_ver}/.unpack_ok"
fi
cd "/usr/src/qtsvg-${qt_ver}"
rm -fr CMakeCache.txt
"${QT_BASE_DIR}/bin/qt-configure-module" .
cmake --build . --parallel
cmake --install .
if [ ! -f "/usr/src/qttools-${qt_ver}/.unpack_ok" ]; then
  qttools_url="https://download.qt.io/official_releases/qt/${qt_major_ver}/${qt_ver}/submodules/qttools-everywhere-src-${qt_ver}.tar.xz"
  retry curl -kSL --compressed "${qttools_url}" \| tar Jxf - -C "/usr/src/qttools-${qt_ver}" --strip-components 1
  touch "/usr/src/qttools-${qt_ver}/.unpack_ok"
fi
cd "/usr/src/qttools-${qt_ver}"
rm -fr CMakeCache.txt
"${QT_BASE_DIR}/bin/qt-configure-module" .
cat config.summary
cmake --build . --parallel
cmake --install .

# Remove qt-wayland until next release: https://bugreports.qt.io/browse/QTBUG-104318
# qt-wayland
#if [ ! -f "/usr/src/qtwayland-${qt_ver}/.unpack_ok" ]; then
#  qtwayland_url="https://download.qt.io/official_releases/qt/${qt_major_ver}/${qt_ver}/submodules/qtwayland-everywhere-src-${qt_ver}.tar.xz"
#  retry curl -kSL --compressed "${qtwayland_url}" \| tar Jxf - -C "/usr/src/qtwayland-${qt_ver}" --strip-components 1
#  touch "/usr/src/qtwayland-${qt_ver}/.unpack_ok"
#fi
#cd "/usr/src/qtwayland-${qt_ver}"
#rm -fr CMakeCache.txt
#"${QT_BASE_DIR}/bin/qt-configure-module" .
#cat config.summary
#cmake --build . --parallel
#cmake --install .

# install qt6gtk2 for better look
if [ ! -d "/usr/src/qt6gtk2/" ]; then
  qt6gtk2_git_url="https://github.com/trialuser02/qt6gtk2.git"
  if [ x"${USE_CHINA_MIRROR}" = x1 ]; then
    qt6gtk2_git_url="https://ghproxy.com/${qt6gtk2_git_url}"
  fi
  retry git clone --depth 1 --recursive "${qt6gtk2_git_url}" "/usr/src/qt6gtk2/"
fi
cd "/usr/src/qt6gtk2/"
git pull
git clean -fdx
qmake
make -j$(nproc) install

# build latest boost
boost_ver="$(retry curl -ksSfL --compressed https://www.boost.org/users/download/ \| grep "'>Version\s*'" \| sed -r "'s/.*Version\s*([^<]+).*/\1/'" \| head -1)"
echo "boost version ${boost_ver}"
mkdir -p "/usr/src/boost-${boost_ver}"
if [ ! -f "/usr/src/boost-${boost_ver}/.unpack_ok" ]; then
  boost_latest_url="https://sourceforge.net/projects/boost/files/boost/${boost_ver}/boost_${boost_ver//./_}.tar.bz2/download"
  retry curl -kSL "${boost_latest_url}" \| tar -jxf - -C "/usr/src/boost-${boost_ver}" --strip-components 1
  touch "/usr/src/boost-${boost_ver}/.unpack_ok"
fi
cd "/usr/src/boost-${boost_ver}"
if [ ! -f ./b2 ]; then
  ./bootstrap.sh
fi
./b2 -d0 -q install --with-system variant=release link=shared runtime-link=shared
cd "/usr/src/boost-${boost_ver}/tools/build"
if [ ! -f ./b2 ]; then
  ./bootstrap.sh
fi
./b2 -d0 -q install variant=release link=shared runtime-link=shared

# build libtorrent-rasterbar
echo "libtorrent-rasterbar branch: ${LIBTORRENT_BRANCH}"
libtorrent_git_url="https://github.com/arvidn/libtorrent.git"
if [ x"${USE_CHINA_MIRROR}" = x1 ]; then
  libtorrent_git_url="https://ghproxy.com/${libtorrent_git_url}"
fi
if [ ! -d "/usr/src/libtorrent-rasterbar-${LIBTORRENT_BRANCH}/" ]; then
  retry git clone --depth 1 --recursive --shallow-submodules --branch "${LIBTORRENT_BRANCH}" \
    "${libtorrent_git_url}" \
    "/usr/src/libtorrent-rasterbar-${LIBTORRENT_BRANCH}/"
fi
cd "/usr/src/libtorrent-rasterbar-${LIBTORRENT_BRANCH}/"
if ! git pull; then
  # if pull failed, retry clone the repository.
  cd /
  rm -fr "/usr/src/libtorrent-rasterbar-${LIBTORRENT_BRANCH}/"
  retry git clone --depth 1 --recursive --shallow-submodules --branch "${LIBTORRENT_BRANCH}" \
    "${libtorrent_git_url}" \
    "/usr/src/libtorrent-rasterbar-${LIBTORRENT_BRANCH}/"
  cd "/usr/src/libtorrent-rasterbar-${LIBTORRENT_BRANCH}/"
fi
rm -fr build/CMakeCache.txt
cmake \
  -B build \
  -G "Ninja" \
  -DCMAKE_BUILD_TYPE="Release" \
  -DCMAKE_CXX_STANDARD="17"
cmake --build build
cmake --install build
# force refresh ld.so.cache
ldconfig

# build qbittorrent
cd "${SELF_DIR}/../../"
rm -fr build/CMakeCache.txt


cmake \
  -B build \
  -G "Ninja" \
  -DQT6=ON \
  -DCMAKE_PREFIX_PATH="${QT_BASE_DIR}/lib/cmake/" \
  -DCMAKE_BUILD_TYPE="Release" \
  -DCMAKE_CXX_STANDARD="17" \
  -DCMAKE_INSTALL_PREFIX="/tmp/qbee/AppDir/usr"
cmake --build build
rm -fr /tmp/qbee/
cmake --install build
# build AppImage
linuxdeploy_qt_download_url="https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage"
if [ x"${USE_CHINA_MIRROR}" = x1 ]; then
  linuxdeploy_qt_download_url="https://ghproxy.com/${linuxdeploy_qt_download_url}"
fi
[ -x "/tmp/linuxdeploy-plugin-qt-x86_64.AppImage" ] || retry curl -kSLC- -o /tmp/linuxdeploy-plugin-qt-x86_64.AppImage "${linuxdeploy_qt_download_url}"
chmod -v +x '/tmp/linuxdeploy-plugin-qt-x86_64.AppImage'

linuxdeploy_qt2_download_url="https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20220822-1/linuxdeploy-x86_64.AppImage"
if [ x"${USE_CHINA_MIRROR}" = x1 ]; then
  linuxdeploy_qt2_download_url="https://ghproxy.com/${linuxdeploy_qt2_download_url}"
fi
[ -x "/tmp/linuxdeploy-x86_64.AppImage" ] || retry curl -kSLC- -o /tmp/linuxdeploy-x86_64.AppImage "${linuxdeploy_qt2_download_url}"
chmod -v +x '/tmp/linuxdeploy-x86_64.AppImage'



cd "/tmp/qbee"
ln -svf usr/share/icons/hicolor/scalable/apps/qbittorrent.svg /tmp/qbee/AppDir/
ln -svf qbittorrent.svg /tmp/qbee/AppDir/.DirIcon
mkdir -p "/tmp/qbee/AppDir/apprun-hooks/"
cat >/tmp/qbee/AppDir/apprun-hooks/setup_env.sh <<EOF
# this file is called from AppRun so 'root_dir' will point to where AppRun is
root_dir="\$(readlink -f "\$(dirname "\$0")")"

# Insert the default values because after the test we prepend our path
# and it will create problems with DEs (eg KDE) that don't set the variable
# and rely on the default paths
if [[ -z \${XDG_DATA_DIRS} ]]; then
    XDG_DATA_DIRS="/usr/local/share/:/usr/share/"
fi

export XDG_DATA_DIRS="\${root_dir}/usr/share:\${XDG_DATA_DIRS}"
export QT_QPA_PLATFORMTHEME=gtk3
case "\${QT_QPA_PLATFORMTHEME}" in
    *gtk2*)
        export QT_QPA_PLATFORMTHEME=qt6gtk2
        ;;

        *)
        export QT_QPA_PLATFORMTHEME=gtk3
        ;;
esac

case "\${QT_STYLE_OVERRIDE}" in
    *gtk2*)
        export QT_QPA_PLATFORMTHEME=qt6gtk2
        unset QT_STYLE_OVERRIDE
        ;;
esac

EOF

ls -al /tmp
ls -al /tmp/qbee
cd "/tmp/qbee"
export EXTRA_QT_PLUGINS="styles;iconengines"
APPIMAGE_EXTRACT_AND_RUN=1  \
  OUTPUT='qBittorrent-x86_64.AppImage' \
  /tmp/linuxdeploy-x86_64.AppImage --appdir="/tmp/qbee/AppDir" --output=appimage  --plugin qt

cp -fv /tmp/qbee/qBittorrent*.AppImage* "${SELF_DIR}/"