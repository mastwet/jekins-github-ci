# jekins-github-ci

用 Docker 搭一个能在受限网络（GitHub 直连不稳、Docker Hub 不可达）里跑 GitHub CI 的 Jenkins。
仓库包含完整镜像定义、初始化脚本，以及两个已经跑通的验证 job：一个 Maven 示例和
[agent-vivy](https://github.com/ProjectViVy/agent-vivy) CI 的 Linux 移植。

## 已验证结果

| Job | 内容 | 结果 |
|---|---|---|
| `github-ci-demo` | clone 公开仓库 → Maven 构建 → 运行 jar | build #3 SUCCESS |
| `vivy-ci` | 11 个 stage 的 Linux 版 CI | build #2 SUCCESS，8 分 29 秒 |

`vivy-ci` 的 stage：Checkout → PrepareLaputa（调用仓库原生 `ensure-laputa.ps1`，pwsh）→
BootstrapTest → FmtCheck → UiBuild → GoVet → GoTest → HeadlessCompile → PluginCI
（遍历所有插件子模块）→ UiCore（typecheck + test）→ I18nCheck。

跳过的 Windows 专属步骤：cold-dev smoke（`dev.ps1`）、diva-recall / test-memory-loop 脚本、
browser/Playwright lane。原 workflow 本身就是跑在 `windows-latest` 上的。

## 快速开始

```bash
docker compose up -d --build
```

访问 http://localhost:8080 ，默认账号 `admin` / `admin123`（登录后请修改）。
首次启动由 `init.groovy.d` 自动完成 Jenkins URL、管理员账号、授权策略和插件加载，无需向导。

创建/更新 vivy-ci job：

```bash
bash vivy-ci/create-job.sh
```

手动触发构建：

```bash
curl -u admin:admin123 -X POST http://localhost:8080/job/vivy-ci/build
```

## 镜像内置工具链

| 工具 | 版本 | 来源 |
|---|---|---|
| Jenkins | LTS（2.580.1） | `docker.m.daocloud.io` |
| Maven | 3.9.9 | Maven Central（依赖走阿里云镜像） |
| Go | 1.26.4 | 阿里云镜像 |
| Node.js | 24.22.0 | 阿里云镜像 |
| pnpm | 11.19.0 | npmmirror |
| PowerShell | 7.6.7 | gh-proxy 转发 |

环境变量固定了 `GOPROXY=https://goproxy.cn,direct`、`NPM_CONFIG_REGISTRY=https://registry.npmmirror.com`，
并关闭了 PowerShell/.NET 的遥测。

## 网络适配

| 问题 | 解决方式 | 位置 |
|---|---|---|
| Docker Hub 不可达 | daocloud 镜像源 | `Dockerfile` 的 `FROM` |
| github.com git 协议不可达 | `url.insteadOf` 重写到 gh-proxy.com | `Dockerfile`，系统级 gitconfig |
| Maven Central 慢 | 阿里云 public 镜像 | `maven-settings.xml` |
| npm 慢 | npmmirror | `Dockerfile` 环境变量 |
| Jenkins 首次向导阻塞自动化 | init.groovy.d 初始化脚本 | `init.groovy.d/01-basic-config.groovy` |
| GitHub CI 插件 | jenkins-plugin-cli 预装 | `plugins.txt` |

git 重写必须是系统/全局级别：仓库本地的 gitconfig 在 clone 初始化阶段不生效。

## 接入自己的仓库

### 公开仓库

新建 Pipeline item → Pipeline script from SCM → Git → Repository URL 填
`https://github.com/<user>/<repo>.git`（clone 自动走 gh-proxy），Script Path 指向仓库里的 Jenkinsfile。

### 私有仓库

Manage Jenkins → Credentials → 添加 Username/Password 凭据：

- Username: GitHub 用户名
- Password: Personal Access Token（classic，勾选 `repo` 权限）
- 建议同时勾选 "Treat username as secret"

然后在 Job 配置的 SCM 里选择该凭据。

### 推送自动触发

- **轮询（无需公网）**：Job 配置勾选 `Poll SCM`，如 `H/5 * * * *`
- **Webhook（需要公网可达）**：`cloudflared tunnel --url http://localhost:8080` 或 ngrok，
  将 Jenkins URL 改为公网地址，在 GitHub 仓库 Settings → Webhooks 添加
  `https://<公网地址>/github-webhook/`（Content type `application/json`，仅 push 事件）

## 常用命令

```bash
docker compose logs -f jenkins          # 看日志
docker compose restart jenkins          # 重启
docker compose down                     # 停止（保留数据卷）
docker compose down -v                  # 停止并清空数据（重置 Jenkins）
```

## 文件说明

- `Dockerfile` — 定制镜像：Maven、git 重写、插件预装、Go/Node/pnpm/pwsh 工具链
- `docker-compose.yml` — Jenkins 服务定义（端口、数据卷、健康检查）
- `plugins.txt` — 插件清单（git/github/github-branch-source/pipeline 等）
- `maven-settings.xml` — Maven 阿里云镜像配置
- `init.groovy.d/01-basic-config.groovy` — 初始化 URL、admin 账号、授权策略
- `demo-job-config.xml` — `github-ci-demo` job 定义（jenkins-docs/simple-java-maven-app）
- `test-ci/Jenkinsfile` — 最小流水线模板
- `vivy-ci/pipeline.groovy` — agent-vivy CI 的 Linux 移植
- `vivy-ci/create-job.sh` — 通过 REST API 创建/更新 `vivy-ci` job

## 注意

- `admin/admin123` 只是本地开发默认值，部署到可被访问的网络前务必修改；
  `docker-compose.yml` 目前把 8080 暴露在所有网卡上。
- gh-proxy 重写只适用于当前网络环境；能直连 GitHub 的环境可以删掉 Dockerfile 里对应的
  `git config --system` 那行。
- `vivy-ci` 需要访问 `ProjectViVy/agent-vivy` 及其 pin 住的 `laputa` 兄弟仓库，构建时会在
  工作区外多检出目录 `laputa`。
