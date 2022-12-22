#!/bin/bash -e

# This scrip is for building AppImage
# Please run this scrip in docker image: ubuntu:18.04
# E.g: docker run --rm -v `git rev-parse --show-toplevel`:/build ubuntu:18.04 /build/.github/workflows/build_appimage.sh
# If you need keep store build cache in docker volume, just like:
#   $ docker volume create qbee-cache
#   $ docker run --rm -v `git rev-parse --show-toplevel`:/build -v qbee-cache:/var/cache/apt -v qbee-cache:/usr/src ubuntu:18.04 /build/.github/workflows/build_appimage.sh
# Artifacts will copy to the same directory.

set -o pipefail

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
root_dir="$(readlink -f "$(dirname "$0")")"

# Insert the default values because after the test we prepend our path
# and it will create problems with DEs (eg KDE) that don't set the variable
# and rely on the default paths
if [[ -z ${XDG_DATA_DIRS} ]]; then
    XDG_DATA_DIRS="/usr/local/share/:/usr/share/"
fi

export XDG_DATA_DIRS="${root_dir}/usr/share:${XDG_DATA_DIRS}"

case "${QT_QPA_PLATFORMTHEME}" in
    *gtk2*)
        export QT_QPA_PLATFORMTHEME=qt6gtk2
        ;;

        *)
        export QT_QPA_PLATFORMTHEME=gtk3
        ;;
esac

case "${QT_STYLE_OVERRIDE}" in
    *gtk2*)
        export QT_QPA_PLATFORMTHEME=qt6gtk2
        unset QT_STYLE_OVERRIDE
        ;;
esac

EOF

ls -al /tmp
ls -al /tmp/qbee
cd "/tmp/qbee"
APPIMAGE_EXTRACT_AND_RUN=1 \
  OUTPUT='qBittorrent-x86_64.AppImage' \
  /tmp/linuxdeploy-x86_64.AppImage --appdir="/tmp/qbee/AppDir" --output=appimage  --plugin qt

cp -fv /tmp/qbee/qBittorrent*.AppImage* "${SELF_DIR}/"