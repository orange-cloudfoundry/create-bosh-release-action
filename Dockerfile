FROM ruby:alpine@sha256:e5c30595c6a322bc3fbaacd5e35d698a6b9e6d1079ab0af09ffe52f5816aec3b

RUN apk add git curl jq bash

# renovate: datasource=github-releases depName=cloudfoundry/bosh-cli
ENV BOSH_VERSION=7.9.4
RUN curl -sL https://github.com/cloudfoundry/bosh-cli/releases/download/v${BOSH_VERSION}/bosh-cli-${BOSH_VERSION}-linux-amd64 | \
  install /dev/stdin /usr/local/bin/bosh && bosh --version

# renovate: datasource=github-releases depName=carvel-dev/vendir
ENV VENDIR_VERSION=0.43.1
RUN curl -sL https://github.com/carvel-dev/vendir/releases/download/v${VENDIR_VERSION}/vendir-linux-amd64 | \
  install /dev/stdin /usr/local/bin/vendir && vendir -v

# renovate: datasource=github-releases depName=mikefarah/yq
ENV YQ_VERSION="4.45.1"
RUN echo "Installing yq version ${YQ_VERSION}" ; \
    curl -L "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" -o /usr/local/bin/yq && \
    chmod +rx /usr/local/bin/yq && \
    /usr/local/bin/yq --version

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
