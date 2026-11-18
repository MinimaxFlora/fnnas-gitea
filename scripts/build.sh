#!/usr/bin/env bash
# 构建 fnOS 应用包（.fpk）
#
#   ./scripts/build.sh                      # 自动取上游最新 tag，编译 amd64 + arm64 并打包
#   ./scripts/build.sh --tag v28.4.0        # 指定上游 tag
#   ./scripts/build.sh --arch amd64         # 只构建一个架构
#   ./scripts/build.sh --skip-frontend      # 复用已构建的前端资源
#
# 依赖：git、go >= 1.27、node >= 22.18、pnpm >= 11、tar、curl
# 产物：dist/gitea_<版本>_<架构>.fpk 与 SHA256SUMS

set -euo pipefail

APP_NAME="gitea"
UPSTREAM_REPO="go-gitea/gitea"
UPSTREAM_URL="https://github.com/${UPSTREAM_REPO}.git"
TAGS="bindata sqlite sqlite_unlock_notify"
FNPACK_VERSION="1.2.3"
FNPACK_URL="https://static2.fnnas.com/fnpack/fnpack-${FNPACK_VERSION}-linux-amd64"
MIN_GO="1.27"
MIN_NODE_MAJOR="22"
# 内置 Gitea Runner（Actions 执行器）
RUNNER_VERSION="6.0.0"
RUNNER_URL_BASE="https://dl.gitea.com/gitea-runner/${RUNNER_VERSION}"
# 默认主题（版本号与 Gitea 大版本保持一致）
THEME_REPO="lutinglt/gitea-github-theme"
THEME_ASSET="theme-github-extra-pink.tar.gz"

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.build}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"
TAG=""
ARCHS="amd64 arm64"
SKIP_FRONTEND=0

info() { printf '\033[0;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG="${2:?--tag 需要版本号}"; shift 2 ;;
        --tag=*) TAG="${1#*=}"; shift ;;
        --arch) ARCHS="${2:?--arch 需要 amd64 或 arm64}"; shift 2 ;;
        --arch=*) ARCHS="${1#*=}"; shift ;;
        --skip-frontend) SKIP_FRONTEND=1; shift ;;
        --out) OUT_DIR="${2:?--out 需要目录}"; shift 2 ;;
        -h|--help) usage ;;
        *) die "未知参数: $1" ;;
    esac
done

case " $ARCHS " in
    *" amd64 "*|*" arm64 "*) ;;
    *) die "--arch 只支持 amd64 / arm64（可空格分隔写多个）" ;;
esac

# ---------------------------------------------------------------------------
# 工具链
# ---------------------------------------------------------------------------
for p in "$HOME/opt/go/bin" "$HOME/opt/node/bin" "$HOME/.local/bin"; do
    [ -d "$p" ] && PATH="$p:$PATH"
done
export PATH

need() { command -v "$1" >/dev/null 2>&1 || die "缺少依赖：$1"; }
need git; need curl; need tar; need sha256sum

command -v go >/dev/null 2>&1 || die "未找到 go，请安装 Go >= ${MIN_GO}（见 README）"
command -v node >/dev/null 2>&1 || die "未找到 node，请安装 Node.js >= ${MIN_NODE_MAJOR}（见 README）"
command -v pnpm >/dev/null 2>&1 || die "未找到 pnpm，请安装 pnpm >= 11（npm i -g pnpm@11）"

GO_VER=$(go env GOVERSION | sed 's/go//')
NODE_VER=$(node -v | sed 's/^v//')
info "go ${GO_VER} / node ${NODE_VER} / pnpm $(pnpm -v)"

# ---------------------------------------------------------------------------
# 上游 tag
# ---------------------------------------------------------------------------
resolve_tag() {
    local t=""
    t=$(curl -fsSL --retry 3 "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest" \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1) || true
    if [ -z "$t" ]; then
        warn "GitHub API 不可用，改用 git ls-remote 解析最新 tag"
        t=$(git ls-remote --tags --refs "$UPSTREAM_URL" \
            | awk -F/ '{print $NF}' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)
    fi
    [ -n "$t" ] || die "无法确定上游最新 tag，请用 --tag 手动指定"
    printf '%s' "$t"
}

if [ -z "$TAG" ]; then
    TAG=$(resolve_tag)
fi
case "$TAG" in
    v*) ;;
    *) TAG="v${TAG}" ;;
esac
VERSION="${TAG#v}"
info "上游 tag：${TAG}（应用版本 ${VERSION}）"

mkdir -p "$BUILD_DIR" "$OUT_DIR"

# ---------------------------------------------------------------------------
# 源码
# ---------------------------------------------------------------------------
SRC="$BUILD_DIR/src-${VERSION}"
if [ ! -d "$SRC/.git" ]; then
    info "克隆 ${UPSTREAM_URL} @ ${TAG}"
    rm -rf "$SRC"
    git clone --depth 1 --branch "$TAG" "$UPSTREAM_URL" "$SRC"
else
    info "复用源码目录 $SRC"
    git -C "$SRC" fetch --depth 1 origin "refs/tags/${TAG}:refs/tags/${TAG}" >/dev/null 2>&1 || true
    git -C "$SRC" checkout -q --detach "$TAG"
fi
info "源码 HEAD: $(git -C "$SRC" rev-parse --short HEAD)（$(git -C "$SRC" describe --tags --always 2>/dev/null || echo "$TAG")）"

# ---------------------------------------------------------------------------
# 前端资源（两个架构共用）
# ---------------------------------------------------------------------------
FRONTEND_STAMP="$BUILD_DIR/frontend-${VERSION}.done"
if [ "$SKIP_FRONTEND" = "1" ] && [ -f "$FRONTEND_STAMP" ]; then
    info "跳过前端构建（使用已有产物）"
elif [ -f "$FRONTEND_STAMP" ] && [ -d "$SRC/public/assets" ]; then
    info "前端资源已存在，跳过 vite build"
else
    info "安装前端依赖（pnpm install --frozen-lockfile）"
    ( cd "$SRC" && pnpm install --frozen-lockfile )
    info "构建前端资源（vite build）"
    ( cd "$SRC" && pnpm exec vite build )
    [ -d "$SRC/public/assets" ] || die "前端构建失败：未生成 public/assets"
    touch "$FRONTEND_STAMP"
fi

# ---------------------------------------------------------------------------
# 生成内嵌资源（bindata）
# ---------------------------------------------------------------------------
GEN_STAMP="$BUILD_DIR/generate-${VERSION}.done"
if [ ! -f "$GEN_STAMP" ] || [ ! -f "$SRC/modules/public/bindata.dat" ]; then
    info "生成内嵌资源（go generate）"
    ( cd "$SRC" && CGO_ENABLED=0 go generate -tags "$TAGS" ./... )
    [ -f "$SRC/modules/public/bindata.dat" ] || die "go generate 未生成 bindata.dat"
    touch "$GEN_STAMP"
else
    info "内嵌资源已生成，跳过 go generate"
fi

# ---------------------------------------------------------------------------
# 主题（GitHub Pink，架构无关，随包分发）
# ---------------------------------------------------------------------------
THEME_DIR="$BUILD_DIR/theme-${VERSION}"
THEME_URL="https://github.com/${THEME_REPO}/releases/download/v${VERSION}/${THEME_ASSET}"
if [ -d "$THEME_DIR" ] && ls "$THEME_DIR"/*.css >/dev/null 2>&1; then
    info "主题已下载，跳过：$THEME_DIR"
else
    info "下载主题 ${THEME_ASSET}（v${VERSION}）"
    THEME_TGZ="$BUILD_DIR/theme-${VERSION}.tar.gz"
    if ! curl -fsSL --retry 3 -o "$THEME_TGZ" "$THEME_URL"; then
        die "主题下载失败：$THEME_URL（该 Gitea 版本可能尚未发布对应主题）"
    fi
    rm -rf "$THEME_DIR"
    mkdir -p "$THEME_DIR"
    tar -xzf "$THEME_TGZ" -C "$THEME_DIR" --strip-components=1 || die "主题解包失败"
    ls "$THEME_DIR"/*.css >/dev/null 2>&1 || die "主题包内没有 css 文件"
fi
info "主题文件：$(ls -1 "$THEME_DIR"/*.css | xargs -n1 basename | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# 编译 + 打包
# ---------------------------------------------------------------------------
FNPACK="$BUILD_DIR/fnpack"
if [ ! -x "$FNPACK" ]; then
    info "下载 fnpack ${FNPACK_VERSION}"
    curl -fsSL --retry 3 -o "$FNPACK" "$FNPACK_URL"
    chmod +x "$FNPACK"
fi
"$FNPACK" --help >/dev/null 2>&1 || die "fnpack 无法执行（$FNPACK）"

platform_of() {
    case "$1" in
        amd64) echo x86 ;;
        arm64) echo arm ;;
        *) die "未知架构 $1" ;;
    esac
}

pack_one() {
    local arch="$1" platform pkg fpk_name

    platform=$(platform_of "$arch")
    local bin="$BUILD_DIR/bin-${VERSION}/gitea-${arch}"
    mkdir -p "$(dirname "$bin")"

    info "编译 gitea（linux/${arch}，CGO 关闭）"
    ( cd "$SRC" && \
      CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -trimpath \
        -tags "$TAGS" \
        -ldflags "-s -w -X main.Version=${VERSION} -X main.Tags=${TAGS// /,}" \
        -o "$bin" . )
    [ -s "$bin" ] || die "编译失败：$bin 为空"
    info "二进制 $(du -h "$bin" | cut -f1)：$(file -b "$bin" 2>/dev/null || true)"

    # Gitea Runner（与当前架构一致）
    local runner="$BUILD_DIR/bin-${VERSION}/gitea-runner-${arch}"
    if [ ! -x "$runner" ]; then
        local runner_url="${RUNNER_URL_BASE}/gitea-runner-${RUNNER_VERSION}-linux-${arch}"
        info "下载 Gitea Runner ${RUNNER_VERSION}（linux/${arch}）"
        curl -fsSL --retry 3 -o "$runner" "$runner_url" || die "Runner 下载失败：$runner_url"
        chmod +x "$runner"
        local runner_sha
        runner_sha=$(curl -fsSL --retry 3 "${runner_url}.sha256" 2>/dev/null | awk '{print $1}') || true
        if [ -n "$runner_sha" ]; then
            echo "${runner_sha}  ${runner}" | sha256sum -c - >/dev/null || die "Runner 校验失败（sha256 不匹配）"
            info "Runner 校验通过（sha256 ${runner_sha:0:12}…）"
        else
            warn "未取到 Runner 的 sha256，跳过校验"
        fi
    fi

    pkg="$BUILD_DIR/pkg-${VERSION}-${arch}"
    rm -rf "$pkg"
    mkdir -p "$pkg/app/ui/images"

    cp "$ROOT_DIR/manifest" "$pkg/manifest"
    cp -a "$ROOT_DIR/cmd" "$pkg/cmd"
    cp -a "$ROOT_DIR/config" "$pkg/config"
    cp -a "$ROOT_DIR/wizard" "$pkg/wizard"
    cp "$ROOT_DIR/ICON.PNG" "$ROOT_DIR/ICON_256.PNG" "$pkg/"
    cp "$ROOT_DIR/app/ui/config" "$pkg/app/ui/config"
    cp "$ROOT_DIR/app/ui/images/icon_64.png" "$ROOT_DIR/app/ui/images/icon_256.png" "$pkg/app/ui/images/"

    cp "$bin" "$pkg/app/gitea"
    chmod 755 "$pkg/app/gitea"
    cp "$runner" "$pkg/app/gitea-runner"
    chmod 755 "$pkg/app/gitea-runner"

    cp "$ROOT_DIR/app/smtp_test.py" "$pkg/app/smtp_test.py"
    chmod 755 "$pkg/app/smtp_test.py"

    mkdir -p "$pkg/app/theme/github-pink"
    cp "$THEME_DIR"/*.css "$pkg/app/theme/github-pink/"
    chmod 644 "$pkg/app/theme/github-pink"/*.css
    chmod 755 "$pkg"/cmd/*

    # 版本 / 架构
    sed -i "s|^version  *=.*|version               = ${VERSION}|" "$pkg/manifest"
    sed -i "s|^platform  *=.*|platform              = ${platform}|" "$pkg/manifest"

    # 静态检查：脚本语法
    local f
    for f in "$pkg"/cmd/*; do
        bash -n "$f" || die "脚本语法错误：$f"
    done
    grep -q "= ${VERSION}" "$pkg/manifest" || die "manifest 版本替换失败"
    grep -q "= ${platform}" "$pkg/manifest" || die "manifest 架构替换失败"

    info "fnpack build（${arch}）"
    ( cd "$OUT_DIR" && "$FNPACK" build --directory "$pkg" )

    fpk_name="${APP_NAME}_${VERSION}_${arch}.fpk"
    if [ -f "$OUT_DIR/${APP_NAME}.fpk" ]; then
        mv -f "$OUT_DIR/${APP_NAME}.fpk" "$OUT_DIR/$fpk_name"
    fi
    [ -f "$OUT_DIR/$fpk_name" ] || die "打包失败：未生成 $fpk_name"
    info "生成 $OUT_DIR/$fpk_name（$(du -h "$OUT_DIR/$fpk_name" | cut -f1)）"
}

for arch in $ARCHS; do
    pack_one "$arch"
done

info "生成校验和"
( cd "$OUT_DIR" && sha256sum "${APP_NAME}_${VERSION}"_*.fpk > SHA256SUMS && cat SHA256SUMS )

info "完成：版本 ${VERSION}，架构 $(echo $ARCHS | tr ' ' ',')"
