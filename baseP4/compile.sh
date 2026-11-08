#!/bin/bash
cd "$(dirname "$0")"
docker run --rm -v "$PWD/p4:/work" -w /work p4lang/p4c \
  p4c-bm2-ss --p4v 16 --p4runtime-files build/upf.p4info.txt --p4runtime-format text \
  -o build/upf.json upf.p4
