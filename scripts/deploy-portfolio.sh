#!/bin/bash
# 服务器侧自动部署(轮询 GitHub main,无需密钥与入站端口)
#
# 特性:
#   - 多镜像轮询(国内访问 GitHub 不稳时的兜底),ls-remote 与下载均带重试
#   - tar.gz 完整性校验(条目数阈值)后才进入发布
#   - 优化流水线:base64 外抽 + WebP q92(与 scripts/optimize-site.sh 一致)
#   - 原子发布:webroot 为指向 releases/<sha> 的符号链接,mv -T 一步切换
#   - 健康检查失败自动回滚到上一版本
#   - flock 防并发;保留最近 N 个版本
#
# 可用环境变量覆盖默认值:
#   REPO_NAME      仓库(默认 Mtx20050731/mao-tianxin-portfolio)
#   SITE_DIR       站点目录(默认 /opt/www/host/mao-portfolio)
#   STATE_DIR      状态/日志目录(默认 ~/.sites)
#   KEEP_RELEASES  保留版本数(默认 3)
#   HEALTHCHECK_URL 发布后健康检查地址,空则跳过(默认空)
#                   示例: https://mao.engine.xxdevs.com:8440/
set -uo pipefail

REPO_NAME="${REPO_NAME:-Mtx20050731/mao-tianxin-portfolio}"
SITE_DIR="${SITE_DIR:-/opt/www/host/mao-portfolio}"
STATE_DIR="${STATE_DIR:-$HOME/.sites}"
KEEP_RELEASES="${KEEP_RELEASES:-3}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"

RELEASES="$SITE_DIR/releases"
STAGE="$STATE_DIR/staging-portfolio"
STATE="$STATE_DIR/.portfolio-sha"
LOCK="$STATE_DIR/.portfolio-deploy.lock"
LOGTAG="$(date '+%F %T')"
MIRRORS=(gh-proxy.com ghproxy.net mirror.ghproxy.com ghfast.top)

mkdir -p "$STATE_DIR" "$RELEASES"
exec 9>"$LOCK"; flock -n 9 || { echo "$LOGTAG 已有部署在跑,跳过"; exit 0; }
rm -rf "$STAGE"; mkdir -p "$STAGE"   # 清理可能残留的半成品

# ---- 1. 查询远端最新 SHA(镜像优先,直连兜底) ----
latest=""
for m in "${MIRRORS[@]}" ""; do
  prefix="${m:+https://$m/}"; url="${prefix}https://github.com/$REPO_NAME.git"
  latest=$(timeout 60 git ls-remote "$url" HEAD 2>/dev/null | awk '{print $1}')
  [ -n "$latest" ] && break
done
[ -n "$latest" ] || { echo "$LOGTAG 所有通道都取不到远端 HEAD,放弃本轮"; exit 1; }

current=$(cat "$STATE" 2>/dev/null)
if [ "$latest" = "$current" ] && [ "${1:-}" != "--force" ]; then
  exit 0   # 无更新,静默退出
fi
echo "$LOGTAG 开始部署 $latest (当前: ${current:-无})"

# ---- 2. 下载 tar.gz(镜像轮询 + curl重试) ----
ok=""
for m in "${MIRRORS[@]}" ""; do
  prefix="${m:+https://$m/}"; url="${prefix}https://codeload.github.com/$REPO_NAME/tar.gz/refs/heads/main"
  if curl -sfL --retry 3 --retry-delay 5 --retry-all-errors --max-time 1800 "$url" -o "$STAGE/src.tar.gz"; then ok=1; break; fi
  echo "$LOGTAG 通道 ${m:-直连} 下载失败,换下一个"
done
[ -n "$ok" ] || { echo "$LOGTAG 全部通道下载失败,保持现状"; exit 1; }

entries=$(tar -tzf "$STAGE/src.tar.gz" 2>/dev/null | wc -l)
[ "$entries" -lt 50 ] && { echo "$LOGTAG tarball 可疑(仅 $entries 条),放弃"; exit 1; }
mkdir -p "$STAGE/tree"
tar -xzf "$STAGE/src.tar.gz" --strip-components=1 -C "$STAGE/tree" || { echo "$LOGTAG 解压失败"; exit 1; }
rm -f "$STAGE/src.tar.gz"

# ---- 3. 优化流水线(base64 外抽 → WebP → 引用重写) ----
cd "$STAGE/tree" || exit 1
bash scripts/optimize-site.sh >/dev/null 2>&1 || echo "$LOGTAG 注意:优化脚本执行异常,按原样部署"
[ -f index.html ] || { echo "$LOGTAG 包内没有 index.html,放弃"; exit 1; }

# ---- 4. 原子发布 ----
short="${latest:0:10}"
prev=$(readlink "$SITE_DIR/webroot" 2>/dev/null || true)
mv "$STAGE/tree" "$RELEASES/$short"
ln -sfn "releases/$short" "$SITE_DIR/webroot.new"
mv -T "$SITE_DIR/webroot.new" "$SITE_DIR/webroot"
echo "$latest" > "$STATE"

# ---- 5. 健康检查,失败自动回滚 ----
if [ -n "$HEALTHCHECK_URL" ]; then
  if ! curl -sf --max-time 20 "$HEALTHCHECK_URL" -o /dev/null; then
    echo "$LOGTAG 健康检查失败,回滚到 $prev"
    if [ -n "$prev" ]; then
      ln -sfn "$prev" "$SITE_DIR/webroot.new" && mv -T "$SITE_DIR/webroot.new" "$SITE_DIR/webroot"
    fi
    exit 1
  fi
fi

# ---- 6. 清理旧版本 ----
ls -1t "$RELEASES" 2>/dev/null | tail -n "+$((KEEP_RELEASES + 1))" | while read -r r; do rm -rf "$RELEASES/$r"; done
rm -rf "$STAGE"
echo "$LOGTAG 部署完成 $short (健康检查: ${HEALTHCHECK_URL:-跳过})"
