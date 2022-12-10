FROM ubuntu:18.04 as stage1

COPY ./ /qbt/

WORKDIR /qbt

RUN ls -al /qbt

RUN .github/workflows/build_appimage.sh

RUN ls -al /qbt

FROM scratch AS export-stage
COPY --from=stage1 /qbt/*.AppImage ./build/