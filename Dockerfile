FROM ubuntu:18.04 as stage1

COPY ./ /qbt/

WORKDIR /qbt/


RUN .github/workflows/build_appimage1.sh
