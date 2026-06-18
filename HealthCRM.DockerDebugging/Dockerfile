FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    tcpdump \
    curl \
    openssl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /captures
CMD ["/bin/bash"]