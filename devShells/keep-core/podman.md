podman build . --target runtime-docker -t keep-core/v2.4.4 --build-a
rg ENVIRONMENT="mainnet" --build-arg VERSION="v2.4.4" --build-arg REVISION="7fd2319444cf4083e19934f202fcc9ef5de54f02"

podman save -o keep-core-v2.4.4.tar localhost/keep-core/v2.4.4:latest

sudo podman load -i keep-core-v2.4.4.tar
