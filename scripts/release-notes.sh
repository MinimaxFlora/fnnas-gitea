#!/usr/bin/env bash
# 生成 GitHub Release 说明（markdown）
#   ./scripts/release-notes.sh --tag v28.4.0 [--dist dist] > RELEASE_NOTES.md
set -euo pipefail

UPSTREAM_REPO="go-gitea/gitea"
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TAG=""
DIST="$ROOT_DIR/dist"

while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG="${2:?}"; shift 2 ;;
        --tag=*) TAG="${1#*=}"; shift ;;
        --dist) DIST="${2:?}"; shift 2 ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
done
[ -n "$TAG" ] || { echo "--tag 必填" >&2; exit 1; }
VERSION="${TAG#v}"

upstream_json=$(mktemp)
if ! curl -fsSL --retry 3 -o "$upstream_json" \
    "https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${TAG}"; then
    echo "warning: 无法获取上游 release 信息，说明中将不含上游更新要点" >&2
    echo '{}' > "$upstream_json"
fi

sha_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || true; }
size_of() { du -h "$1" 2>/dev/null | cut -f1 | tr -d ' ' || true; }

amd="$DIST/gitea_${VERSION}_amd64.fpk"
arm="$DIST/gitea_${VERSION}_arm64.fpk"

cat <<EOF
# Gitea ${TAG} for 飞牛 fnOS

从上游 [Gitea ${TAG}](https://github.com/${UPSTREAM_REPO}/releases/tag/${TAG}) **源码直接编译**，非 Docker，打包为飞牛原生应用（.fpk）。

- 应用标识：\`gitea\`（显示名 **Gitea**）；与官方商店同名，安装前请先卸载或停止官方版（两者都占用 3033）
- 若曾装过旧的测试包 \`gitea-native\`，请先在应用中心卸载它，再安装本包（数据目录不同，不会自动迁移）
- Web：\`http://<NAS-IP>:3033\`
- 内置 SSH：默认 \`2222\`（被占用时安装时会自动顺延到 2223-2229）
- 数据目录：\`/volX/@appdata/gitea\`（安装时选择的存储空间）
EOF

echo
echo "## 安装包"
echo
echo "| 架构 | 文件 | 大小 | SHA256 |"
echo "| --- | --- | --- | --- |"
if [ -f "$amd" ]; then
    echo "| x86 / amd64 | \`gitea_${VERSION}_amd64.fpk\` | $(size_of "$amd") | \`$(sha_of "$amd")\` |"
fi
if [ -f "$arm" ]; then
    echo "| ARM / arm64 | \`gitea_${VERSION}_arm64.fpk\` | $(size_of "$arm") | \`$(sha_of "$arm")\` |"
fi
echo
echo "> 校验：\`sha256sum -c SHA256SUMS\`"

cat <<'EOF'

## 安装

1. 飞牛 **应用中心 → 手动安装**，选择对应架构的 `.fpk`（x86 设备选 amd64，ARM 设备选 arm64）
2. 在安装向导中填写管理员用户名、密码、邮箱，并选择是否允许访客注册
3. 安装完成后在「我的应用」里点击 **打开**，或直接访问 `http://<NAS-IP>:3033`

**升级**：在应用中心直接安装新版 fpk 即可，`cmd/upgrade_init` 会先停止旧进程，数据与配置（含 app.ini、数据库、仓库）全部保留。

## 首次使用要点

- 无需再打开 Gitea 网页安装器：`app.ini` 与 SQLite 数据库在安装时已生成，管理员账号已创建
- 内置 SSH 服务已启用，克隆地址形如 `ssh://gitea@<NAS-IP>:2222/<用户>/<仓库>.git`
- 若开启了飞牛防火墙，请放行 `3033/tcp` 与 `2222/tcp`
- 通过域名/反向代理访问时，请在 **应用设置 → 访问地址** 里把 `ROOT_URL` 改成对外地址，否则仓库地址与邮件链接会指向内网 IP

## 环境要求

- fnOS ≥ 1.1.3100
- 系统需要提供 `git ≥ 2.0`。飞牛自带的 git 可能缺少 `git-remote-https`，如遇 `git: 'remote-https' is not a git command`，请 SSH 登录后执行：
  ```bash
  sudo apt update && sudo apt install -y git libcurl4-gnutls-dev
  ```
  本应用已自动把 `/usr/lib/git-core`、`/var/packages/git/target/*` 加入运行期 PATH。

EOF

body=$(python3 - "$upstream_json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(""); sys.exit()
print(d.get("body") or "")
PY
)

if [ -n "$body" ]; then
    cat <<'EOF'
## 上游更新要点

<details>
<summary>点击展开 Gitea 官方 changelog</summary>

EOF
    printf '%s\n' "$body"
    cat <<'EOF'

</details>
EOF
fi

echo
echo "## 关于本包"
echo
echo "- 构建方式：拉取上游 tag → \`pnpm exec vite build\` 构建前端 → \`CGO_ENABLED=0\` 交叉编译静态二进制（绑定 SQLite、内嵌 bindata 资源）→ \`fnpack build\` 生成 fpk"
echo "- 未修改任何上游业务代码，仅补充飞牛的生命周期脚本与默认配置"
echo "- 上游源码：https://github.com/${UPSTREAM_REPO}/tree/${TAG}"
echo "- 打包项目：https://github.com/MinimaxFlora/fnnas-gitea"
echo "- 本包为社区维护，非飞牛官方应用；问题请到项目仓库反馈"

if [ -n "${EXTRA_NOTES_FILE:-}" ] && [ -f "$EXTRA_NOTES_FILE" ]; then
    echo
    echo "## 本次打包修订"
    echo
    cat "$EXTRA_NOTES_FILE"
fi
