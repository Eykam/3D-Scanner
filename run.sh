#!/bin/bash
yes | docker-compose rm
rm -rf ./dist
cd client && npm run build
cp ./Dockerfile ./dist/Dockerfile
mv ./dist ../dist
cd ..
zig build
cp ./zig-out/bin/3d_scanner ./dist/3d_scanner
docker-compose build
docker-compose up