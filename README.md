# Gitea for 飞牛 fnOS（原生编译版）

把上游 [Gitea](https://github.com/go-gitea/gitea) 的**最新 tag 源码直接编译**，再打包成飞牛 fnOS 原生应用（`.fpk`），提供 x86（amd64）与 ARM（arm64）两种安装包。

飞牛官方应用商店里的 Gitea 版本长期停留在旧版本，且形态是 Docker；本项目用原生二进制替代它：不用 Docker、启动更快、内存占用更小，版本严格跟随上游 tag。

| 项目 | 说明 |
| --- | --- |
| 应用标识 | `gitea-native`（显示名 **Gitea**），与官方商店的 Gitea 互不冲突，可共存 |
| Web 端口 | `3033` |
| SSH 端口 | 内置 SSH 服务，默认 `2222`（被占用时安装时自动顺延 2223–2229） |
| 数据目录 | `/volX/@appdata/gitea-native`（安装时选择的存储空间） |
| 配置目录 | `/volX/@appconf/gitea-native/app.ini` |
| 安装目录 | `/volX/@appcenter/gitea-native`（即 `$TRIM_APPDEST`） |
| 版本策略 | GitHub tag / Release 名称与上游 tag 完全一致（例如 `v28.4.0`） |

## 安装

1. 打开飞牛 **应用中心 → 手动安装**（或「设置 → 手动安装应用」）
2. 按设备架构选择安装包：
   - x86 / amd64：`gitea-native_<版本>_amd64.fpk`
   - ARM / arm64：`gitea-native_<版本>_arm64.fpk`
3. 在安装向导里填写：
   - 管理员用户名（默认 `admin`）
   - 管理员密码（至少 8 位）
   - 管理员邮箱
   - 是否允许访客自助注册（默认不允许）
4. 安装完成后在「我的应用」点 **打开**，或浏览器访问 `http://<NAS-IP>:3033`

安装阶段就会生成 `app.ini`、SQLite 数据库并创建管理员账号，**不需要**再走 Gitea 的网页安装器。

## 从旧版（官方商店 Gitea）迁移

两者的应用标识与数据目录不同，互不影响。如果要彻底改用本项目：

1. 先在应用中心**停止**官方商店的 Gitea（避免占用 3033 端口）
2. 安装本项目的 fpk
3. 如需迁移仓库，用 Gitea 自带命令导出/导入，或直接把旧数据目录里的 `data/gitea-repositories` 复制到 `/volX/@appdata/gitea-native/data/` 后重新扫描
4. 确认新版本可用后，再卸载官方版并删除其数据

> 不建议把本包与官方版同时运行：两者都会占用 3033 端口。

## 升级

在应用中心直接安装新版本 fpk。升级流程会：

1. `cmd/upgrade_init` 停止旧进程
2. 替换 `target` 下的二进制
3. `cmd/upgrade_callback` 修正权限、补齐目录
4. 启动时由 Gitea 自动完成数据库结构迁移

`app.ini`、数据库、仓库、LFS 文件全部保留在原来的数据目录，不会被覆盖。

## 卸载

卸载向导会询问是否删除数据：

- **保留现有文件**：只删除程序，`/volX/@appdata/gitea-native` 保留，重新安装可继续使用
- **清除所有数据**：删除数据与配置目录（不可恢复），脚本只会删除本应用自己的目录

## 目录结构

```
fnnas-gitea/
├── manifest                  # 应用元数据（fnpack 必需）
├── ICON.PNG / ICON_256.PNG   # 64 / 256 图标
├── app/
│   ├── gitea                 # 构建产物（不入库）
│   └── ui/
│       ├── config            # 桌面入口定义
│       └── images/           # 入口图标 icon_64 / icon_256
├── cmd/                      # 生命周期脚本
│   ├── main                  # start / stop / status / log
│   ├── install_init          # 端口、git 检查
│   ├── install_callback      # 生成 app.ini + 创建管理员
│   ├── upgrade_init/_callback
│   ├── uninstall_init/_callback
│   └── config_init/_callback # 应用设置：ROOT_URL、开放注册
├── config/
│   ├── privilege             # 以 package 用户运行（非 root）
│   └── resource
├── wizard/
│   ├── install               # 安装向导
│   ├── config                # 应用设置
│   └── uninstall             # 卸载向导
└── scripts/
    ├── build.sh              # 拉上游 tag → 编译 → fnpack 打包
    └── release-notes.sh      # 生成 Release 说明
```

## 构建

### 依赖

| 工具 | 版本 |
| --- | --- |
| Go | ≥ 1.27（Gitea v28 的 `go.mod` 要求 `go 1.27`） |
| Node.js | ≥ 22.18（前端 `vite build`） |
| pnpm | ≥ 11 |
| 其他 | git、curl、tar、sha256sum |

`fnpack`（飞牛官方打包工具）由脚本自动下载。

### 命令

```bash
# 自动取上游最新 tag，构建 amd64 + arm64 两个 fpk
./scripts/build.sh

# 指定 tag / 单架构
./scripts/build.sh --tag v28.4.0
./scripts/build.sh --tag v28.4.0 --arch amd64

# 产物
dist/gitea-native_28.4.0_amd64.fpk
dist/gitea-native_28.4.0_arm64.fpk
dist/SHA256SUMS
```

脚本实际做的事：

1. `git clone --depth 1 --branch <tag>` 上游源码
2. `pnpm install --frozen-lockfile && pnpm exec vite build` 构建前端资源
3. `go generate -tags "bindata sqlite sqlite_unlock_notify" ./...` 生成内嵌资源
4. `CGO_ENABLED=0 GOOS=linux GOARCH=<arch> go build` 交叉编译（纯 Go SQLite，无 CGO 依赖）
5. 组装 `app/ + cmd/ + config/ + wizard/ + manifest + 图标`
6. `fnpack build` 生成 `.fpk`，并按架构重命名

> 构建建议在 Linux / WSL 下执行；Windows 原生环境需要自行准备上述工具链。

## 自动发版

`.github/workflows/build-release.yml`：

- **每天 03:17 定时检查**上游是否有新 release，有则自动构建并发布
- 也可在 Actions 页面手动触发，指定 tag（留空取最新）或强制重建
- Release 的 **tag 与名称和上游 tag 完全一致**（如 `v28.4.0`），并附两个 fpk 与 `SHA256SUMS`
- Release 说明由 `scripts/release-notes.sh` 生成，包含：架构对照表、SHA256、安装步骤、环境要求，并折叠附上上游官方 changelog

## 运行期约定

全部路径来自 fnOS 注入的环境变量，没有硬编码安装盘：

| 变量 | 用途 |
| --- | --- |
| `TRIM_APPDEST` | 程序安装目录（`target`） |
| `TRIM_PKGVAR` | 数据目录（`data/`、`log/`、`custom/`） |
| `TRIM_PKGETC` | 配置目录（`app.ini`） |
| `TRIM_SERVICE_PORT` | Web 端口（3033） |
| `TRIM_USERNAME` | 应用运行用户（非 root） |

生命周期脚本约定：`start` 成功返回 0、`stop` 幂等、`status` 运行中返回 0 未运行返回 3、未知参数返回 1。

## 常见问题

**克隆/推送报 `git: 'remote-https' is not a git command`**
飞牛自带的 git 缺少 `git-remote-https`。SSH 登录后执行一次：

```bash
sudo apt update && sudo apt install -y git libcurl4-gnutls-dev
```

应用已自动把 `/usr/lib/git-core`、`/usr/libexec/git-core`、`/var/packages/git/target/*` 加入运行期 `PATH`。

**端口 3033 被占用**
安装时 `cmd/install_init` 会检测并阻止安装，请先停止占用该端口的应用（通常是官方商店的 Gitea）。

**通过域名访问，仓库地址却是内网 IP**
在应用设置里把「访问地址」改成 `https://git.example.com/`（必须以 `/` 结尾），保存后会自动重启服务。

**SSH 克隆失败**
确认防火墙放行 `2222/tcp`，并在页面上确认 SSH 端口（被占用时会顺延，实际端口写在 `app.ini` 的 `SSH_PORT`）。

## 免责声明

本包由社区维护，不是飞牛官方应用。上游代码版权归 Gitea 项目所有（MIT），本仓库仅提供飞牛打包所需的生命周期脚本与默认配置。
