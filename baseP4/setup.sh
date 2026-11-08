#!/bin/bash
set -e
cd "$(dirname "$0")"

# 1. fetch the 5GC config folders and .env from the upstream repo (once)
if [ ! -f .env ]; then
  git clone --depth 1 https://github.com/herlesupreeth/docker_open5gs .repo
  for d in nrf scp ausf udr udm smf amf pcf bsf nssf webui; do cp -r ".repo/$d" .; done
  cp .repo/.env .env
  rm -rf .repo
fi
mkdir -p log

# 2. SMF must send N4 (PFCP) to the controller
if grep -q '^UPF_IP=' .env; then
  sed -i 's/^UPF_IP=.*/UPF_IP=172.22.0.200/' .env
else
  echo 'UPF_IP=172.22.0.200' >> .env
fi
grep -nE '172\.22\.0\.(201|210|211)|AMF_IP=' .env || true
echo "check: AMF_IP above must equal the amf address in ueransim-p4/gnb.yaml (172.22.0.10)"

# 3. images
docker pull ghcr.io/herlesupreeth/docker_open5gs:master
docker tag  ghcr.io/herlesupreeth/docker_open5gs:master docker_open5gs
docker pull ghcr.io/herlesupreeth/docker_ueransim:master
docker tag  ghcr.io/herlesupreeth/docker_ueransim:master docker_ueransim
docker pull p4lang/behavioral-model:latest   # base for ./bmv2/Dockerfile
docker pull p4lang/p4c:latest
docker compose build

echo "next: docker compose up -d"
echo "then: docker exec -it webui misc/db/open5gs-dbctl add_ue_with_apn 001010123456790 8baf473f2f8fd09487cccbd7097c6862 8E27B6AF0E692E750F32667A3B14605D internet"
