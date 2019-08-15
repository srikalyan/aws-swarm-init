FROM ubuntu:bionic
MAINTAINER Srikalyan Swayampakula <srikalyansswayam@gmail.com>

# Note: Install libltdl-dev so that docker binary from host can base used in the image
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y jq libltdl-dev python3-pip wget curl && \
    pip3 install -U pip && \
    pip install awscli

COPY entry.sh /

WORKDIR /

CMD ["/entry.sh"]

