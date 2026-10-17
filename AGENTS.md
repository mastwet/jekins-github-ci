# AGENTS.md

本工作区用于构建、运行和验证「在受限网络下跑 GitHub CI 的 Jenkins」。
工具链仓库：https://github.com/mastwet/jekins-github-ci

## 目录与仓库

- 本仓库就是这套工具链：仓库根目录即 Docker build context 和 compose 项目目录，以下命令默认在仓库根目录执行（本地工作区中仓库位于 `jenkins/`）。
- compose 项目名取自目录名：本地目录名为 `jenkins`，数据卷为 `jenkins_jenkins_home`。重命名或移动目录会切换数据卷、看不到已有 job 和历史；要沿用已有数据，请保持本地目录名为 `jenkins`。

## SOP：用 Docker 启动并运行 Jenkins GitHub CI

### 1. 前置条件

- Docker Desktop 已运行，`docker compose version` 可用
- 8080、50000 端口空闲
- 首次构建需要拉取基础镜像和依赖（走镜像源，见第 8 节）

### 2. 启动

```bash
docker compose up -d --build
```

- 首次 `--build` 需要安装 Maven、Go、Node、pnpm、PowerShell 以及 `plugins.txt` 中的插件（含依赖约 83 个），视网络需数分钟到十几分钟；镜像构建完成后再次启动为秒级。
- 日常启动（无构建文件改动）可省略 `--build`：

```bash
docker compose up -d
```

### 3. 等待就绪并登录

```bash
docker compose ps                                                        # STATUS 需出现 (healthy)
curl -fsS -o /dev/null -w '%{http_code}\n' http://localhost:8080/login   # 200
```

打开 http://localhost:8080 ，默认账号 `admin` / `admin123`。

- 首次启动由 `init.groovy.d/01-basic-config.groovy` 自动完成 Jenkins URL、管理员账号和授权策略配置，不需要首次向导。
- 账号只在不存在时创建；在 UI 里改过的密码不会被启动脚本重置。

### 4. 任务与触发

| Job | 定义位置 | 说明 |
|---|---|---|
| `github-ci-demo` | `demo-job-config.xml` | 公开仓库 Maven 示例，验证 clone → build → run 链路 |
| `vivy-ci` | `vivy-ci/pipeline.groovy` | agent-vivy CI 的 Linux 移植，11 个 stage |

全新数据卷上不会自动创建 job（初始化脚本只负责账号和权限），需要执行下面的命令。

创建或更新 `vivy-ci`（需宿主机有 python3；可用 `JENKINS_URL`、`JENKINS_AUTH` 覆盖默认值）：

```bash
bash vivy-ci/create-job.sh
```

创建 demo job（已存在则改用 `/job/github-ci-demo/config.xml` 更新）：

```bash
JAR=$(mktemp)
crumb=$(curl -s -c "$JAR" -u admin:admin123 http://localhost:8080/crumbIssuer/api/json | sed -E 's/.*"crumb":"([^"]+)".*/\1/')
curl -s -o /dev/null -w 'create HTTP %{http_code}\n' -b "$JAR" -u admin:admin123 \
  -H "Jenkins-Crumb: $crumb" -H "Content-Type: application/xml" \
  --data-binary @demo-job-config.xml \
  'http://localhost:8080/createItem?name=github-ci-demo'
rm -f "$JAR"
```

触发构建（Jenkins 开启了 CSRF，必须带 crumb 和同一会话的 cookie；已在 demo job 验证返回 201）：

```bash
JAR=$(mktemp)
crumb=$(curl -s -c "$JAR" -u admin:admin123 http://localhost:8080/crumbIssuer/api/json | sed -E 's/.*"crumb":"([^"]+)".*/\1/')
curl -s -o /dev/null -w 'trigger HTTP %{http_code}\n' -b "$JAR" -u admin:admin123 \
  -H "Jenkins-Crumb: $crumb" -X POST http://localhost:8080/job/vivy-ci/build
rm -f "$JAR"
```

201 表示已入队。查看结果：

```bash
curl -s -u admin:admin123 'http://localhost:8080/job/vivy-ci/lastBuild/api/json?tree=number,result,duration'
```

或直接打开 http://localhost:8080/job/vivy-ci/ 。

### 5. 已验证基线

- `vivy-ci` build #2：SUCCESS，509,695 ms（8 分 29 秒），11 个 stage 全过
- `github-ci-demo` build #5：SUCCESS，27,264 ms（用第 4 节的 REST 命令触发，HTTP 201）
- 容器内版本：Go 1.26.4 / Node v24.22.0 / pnpm 11.19.0 / PowerShell 7.6.7
- 检查命令：

```bash
docker exec jenkins sh -c 'go version; node --version; pnpm --version; pwsh --version'
```

### 6. 停止、重启与重置

```bash
docker compose logs -f jenkins     # 容器日志（构建日志在 job 页面）
docker compose restart jenkins
docker compose down                # 停止，保留数据卷
docker compose down -v             # 危险：删除数据卷（所有 job、构建历史、凭据）
```

`down -v` 属于破坏性操作，执行前必须征得用户明确同意。

### 7. 修改与发布

- 修改 `pipeline.groovy` 后：重新执行 `bash vivy-ci/create-job.sh`。job 是内联的 CpsFlowDefinition，不会自动跟踪文件变化。
- 修改 `Dockerfile`、`plugins.txt` 或 compose 后：`docker compose up -d --build`，数据卷保留。
- 工具链仓库改动：

```bash
git add <files>
git commit -m "<message>"
git push origin main
```

- fetch 走 gh-proxy；push 已配置为直连 GitHub（仓库级 `pushInsteadOf` + `gh auth git-credential`）。不要修改全局 git 配置。
- 主机全局 git 配置会把 `https://github.com/` 的 fetch 重写到 gh-proxy；在本工作区向其他 GitHub 仓库推送时需同样处理，否则会推到 gh-proxy。

### 8. 网络与镜像约束

| 依赖 | 处理方式 |
|---|---|
| Docker Hub | `docker.m.daocloud.io` |
| github.com 的 git clone | 镜像内系统级 `url.insteadOf` 重写到 gh-proxy.com |
| Maven | 阿里云 public 镜像（`maven-settings.xml`） |
| Go modules | `GOPROXY=https://goproxy.cn,direct` |
| npm / pnpm | `registry.npmmirror.com` |
| Go / Node 二进制 | 阿里云镜像 |
| pwsh | gh-proxy 转发的 GitHub release |

关键点：

- git 重写必须是系统/全局级别；仓库本地配置在 clone 初始化阶段不生效。
- gh-proxy 只用于下载，不支持 push。
- 网络环境变化后（例如可以直连 GitHub），可删掉 Dockerfile 中的 `git config --system` 重写。

### 9. vivy-ci 覆盖范围

Stage 顺序：Checkout → PrepareLaputa（原生 `ensure-laputa.ps1` + pwsh）→ BootstrapTest → FmtCheck → UiBuild → GoVet → GoTest → HeadlessCompile → PluginCI → UiCore → I18nCheck。

- GoTest 使用 `-p 1`、跳过 `^TestMemoryLoop`、超时 35m；pipeline 总超时 180m。
- 跳过 Windows 专属步骤：cold-dev smoke（`dev.ps1`）、diva-recall / test-memory-loop 脚本、browser/Playwright lane。
- 构建时会额外检出 `laputa` 到工作区外（`/var/jenkins_home/workspace/laputa`）。
- 修改 pipeline 时注意 Groovy 字符串：含 `$` 的 shell 命令用三单引号，避免解析错误。

### 10. 故障排查

| 现象 | 处理 |
|---|---|
| 8080 无法访问 | `docker compose ps` / `docker compose logs --tail=200 jenkins`；检查端口占用 |
| 登录失败 | 密码可能已在 UI 修改；重置需 `down -v`（破坏性，先确认） |
| REST POST 返回 403 | 缺少 crumb 或 cookie jar 不匹配，按第 4 节模板重试 |
| 构建中 clone 超时 | `docker exec jenkins git config --system --get-regexp '^url\.'` 应指向 gh-proxy；`docker exec jenkins curl -I https://gh-proxy.com` |
| `mvn/go/pwsh: not found` | 镜像不完整，重新 `docker compose up -d --build` |
| pnpm install 失败 | 检查容器内 `NPM_CONFIG_REGISTRY` 是否指向 npmmirror |
| job/历史“消失” | 可能换了目录名导致用了新卷；回到原来的仓库目录（本地为 `jenkins/`）启动 |
| 镜像构建拉取失败 | 检查 daocloud 基础镜像是否可达；必要时更换 Docker Hub 镜像源 |

### 11. 安全

- `admin/admin123` 仅是本地默认值；8080 目前绑定所有网卡（`0.0.0.0`），对外使用前必须改密码或限制网络。
- 不要把 token、PAT 或真实凭据提交进仓库；`jenkins/` 是公开仓库。
- 不要在未确认的情况下执行 `docker compose down -v`、`docker system prune` 等破坏性命令。
