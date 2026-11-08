FROM hashicorp/terraform:1.9
ARG TARGETARCH
ARG KIND_VERSION=v0.27.0
ARG KUBECTL_VERSION=v1.32.2
RUN apk add --no-cache docker-cli curl \
 && curl -fsSLo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${TARGETARCH}" \
 && curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
 && chmod +x /usr/local/bin/kind /usr/local/bin/kubectl
ENTRYPOINT []
