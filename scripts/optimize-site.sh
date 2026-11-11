#!/bin/bash
# 站点优化流水线(幂等,可反复运行):
#   1. 抽取 index.html 内嵌的 base64 图片为独立文件(字节不变,零画质损失)
#   2. >300KB 的 PNG/JPG 转 WebP q92(保留 ICC;视觉无损,失败或更大则保留原文件)
#   3. 重写 index.html 中的引用
# 用法: 在仓库根目录执行  scripts/optimize-site.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
command -v cwebp >/dev/null || { echo "需要 cwebp(brew install webp / apt install webp)"; exit 1; }
[ -f index.html ] || { echo "在仓库根目录找不到 index.html"; exit 1; }

echo "== 1/3 抽取 base64 内嵌图 =="
python3 - <<'PY'
import base64, re, pathlib
p = pathlib.Path("index.html"); html = p.read_text(encoding="utf-8")
pat = re.compile(r"data:image/(png|jpeg);base64,([A-Za-z0-9+/=]+)")
seen = {}
def repl(m):
    ext, data = m.group(1), m.group(2)
    if data not in seen:
        seen[data] = "assets/inline/embed-%02d.%s" % (len(seen), "jpg" if ext == "jpeg" else ext)
        pathlib.Path("assets/inline").mkdir(parents=True, exist_ok=True)
        pathlib.Path(seen[data]).write_bytes(base64.b64decode(data))
    return seen[data]
p.write_text(pat.sub(repl, html), encoding="utf-8")
print("   抽出", len(seen), "张;index.html 现为", p.stat().st_size // 1024, "KB")
PY

echo "== 2/3 大图转 WebP(q92) =="
find assets -type f \( -iname '*.png' -o -iname '*.jpg' \) -size +300k -print0 |
  xargs -0 -P "$(nproc)" -I{} bash -c 'f="{}"; out="${f%.*}.webp"; if cwebp -quiet -q 92 -metadata icc "$f" -o "$out" 2>/dev/null && [ "$(stat -c%s "$out")" -lt "$(stat -c%s "$f")" ]; then rm -f "$f"; echo "   转 $f"; else rm -f "$out"; fi'

echo "== 3/3 重写引用 =="
python3 - <<'PY'
import pathlib
p = pathlib.Path("index.html"); html = p.read_text(encoding="utf-8")
n = 0
for webp in pathlib.Path("assets").rglob("*.webp"):
    for old in (webp.with_suffix(".png"), webp.with_suffix(".jpg")):
        if not old.exists() and str(old) in html:
            html = html.replace(str(old), str(webp)); n += 1
p.write_text(html, encoding="utf-8")
print("   重写", n, "处")
PY
echo "== 完成 =="
