FROM ubuntu:16.04 as builder

ARG CONSTELLATION_VERSION=0.3.5
ARG QUORUM_VERSION=2.2.0

WORKDIR /work

RUN apt-get update && \
    apt-get install -y \
            build-essential \
            git \
            libdb-dev \
            libsodium-dev \
            libtinfo-dev \
            sysvbanner \
            unzip \
            wget \
            wrk \
            zlib1g-dev

RUN wget -q https://github.com/jpmorganchase/constellation/releases/download/v0.3.5-build.1/constellation-0.3.5-ubuntu1604.tar.gz && \
    tar -xvf constellation-$CONSTELLATION_VERSION-ubuntu1604.tar.gz && \
    cp constellation-node /usr/local/bin && \
    chmod 0755 /usr/local/bin/constellation-node && \
    rm -rf constellation-$CONSTELLATION_VERSION-ubuntu1604.tar.gz constellation-node

ENV GOREL go1.10.7.linux-amd64.tar.gz
ENV PATH $PATH:/usr/local/go/bin

RUN wget -q https://storage.googleapis.com/golang/$GOREL && \
    tar xfz $GOREL && \
    mv go /usr/local/go && \
    rm -f $GOREL


RUN git clone https://github.com/jpmorganchase/quorum.git && \
    cd quorum && \
    git checkout v$QUORUM_VERSION && \
    make all && \
    cp build/bin/geth /usr/local/bin && \
    cp build/bin/bootnode /usr/local/bin && \
    cd .. && \
    rm -rf quorum

### Create the runtime image, leaving most of the cruft behind (hopefully...)

FROM ubuntu:16.04

# Install add-apt-repository
RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository ppa:ethereum/ethereum && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libdb-dev \
        libleveldb-dev \
        libsodium-dev \
        zlib1g-dev\
        libtinfo-dev \
        solc && \
    rm -rf /var/lib/apt/lists/*

# Temporary useful tools
#RUN apt-get update && \
#        apt-get install -y iputils-ping net-tools vim

COPY --from=builder \
        /usr/local/bin/constellation-node \
        /usr/local/bin/geth \
        /usr/local/bin/bootnode \
    /usr/local/bin/

CMD ["/qdata/start-node.sh"]
