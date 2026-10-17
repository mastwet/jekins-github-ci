FROM docker.m.daocloud.io/jenkins/jenkins:lts

USER root

# Maven（从 Maven Central 下载，archive.apache.org 在本机网络较慢）
ARG MAVEN_VERSION=3.9.9
RUN curl -fsSL "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/${MAVEN_VERSION}/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
      -o /tmp/maven.tar.gz \
    && tar -xzf /tmp/maven.tar.gz -C /opt \
    && ln -s /opt/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/local/bin/mvn \
    && rm /tmp/maven.tar.gz \
    && mvn -version

# 容器内 git 无法直连 github.com 的 git 协议，用 gh-proxy 镜像转发 clone/fetch
RUN git config --system url."https://gh-proxy.com/https://github.com/".insteadOf "https://github.com/"

# Maven 使用阿里云镜像加速依赖下载
COPY maven-settings.xml /opt/apache-maven-${MAVEN_VERSION}/conf/settings.xml

USER jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt \
    --plugin-download-directory /usr/share/jenkins/ref/plugins

COPY init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/

# ---- agent-vivy CI 工具链 (linux/arm64) ----
USER root

ARG GO_VERSION=1.26.4
ARG NODE_VERSION=24.22.0
ARG PNPM_VERSION=11.19.0
ARG PWSH_VERSION=7.6.7

RUN set -eux; \
    curl -fsSL "https://mirrors.aliyun.com/golang/go${GO_VERSION}.linux-arm64.tar.gz" -o /tmp/go.tgz; \
    tar -xzf /tmp/go.tgz -C /usr/local; \
    rm /tmp/go.tgz; \
    /usr/local/go/bin/go version

RUN set -eux; \
    curl -fsSL "https://mirrors.aliyun.com/nodejs-release/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-arm64.tar.gz" -o /tmp/node.tgz; \
    mkdir -p /usr/local/node; \
    tar -xzf /tmp/node.tgz -C /usr/local/node --strip-components=1; \
    rm /tmp/node.tgz; \
    mkdir -p /usr/local/node/etc; \
    echo "registry=https://registry.npmmirror.com" > /usr/local/node/etc/npmrc; \
    /usr/local/node/bin/node --version

# PowerShell 依赖 ICU（Debian trixie 包名 libicu76，镜像默认未装）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends libicu76; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    curl -fsSL "https://gh-proxy.com/https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-arm64.tar.gz" -o /tmp/pwsh.tgz; \
    mkdir -p /opt/microsoft/powershell/7; \
    tar -xzf /tmp/pwsh.tgz -C /opt/microsoft/powershell/7; \
    chmod +x /opt/microsoft/powershell/7/pwsh; \
    ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh; \
    rm /tmp/pwsh.tgz

ENV PATH="/usr/local/go/bin:/usr/local/node/bin:/opt/microsoft/powershell/7:${PATH}" \
    GOPROXY="https://goproxy.cn,direct" \
    NPM_CONFIG_REGISTRY="https://registry.npmmirror.com" \
    COREPACK_NPM_REGISTRY="https://registry.npmmirror.com" \
    POWERSHELL_TELEMETRY_OPTOUT="1" \
    POWERSHELL_UPDATECHECK="Off" \
    DOTNET_CLI_TELEMETRY_OPTOUT="1"

RUN set -eux; \
    npm install -g pnpm@${PNPM_VERSION}; \
    node --version; \
    pnpm --version; \
    go version; \
    pwsh --version

USER jenkins
