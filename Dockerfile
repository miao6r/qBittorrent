FROM ubuntu:18.04 as stage1

COPY ./ /qbt/

WORKDIR /qbt/


RUN .github/workflows/build_appimage.sh

FROM scratch AS export-stage
COPY --from=stage1 /qbt/.github/workflows/*.AppImage ./build/
COPY --from=stage1  /tmp/qbee/usr/bin/qbittorrent ./build/