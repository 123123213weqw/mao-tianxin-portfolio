# 毛恬昕 · 创作档案(个人作品集)

视觉设计作品集单页站点:品牌、IP、UI/VIS、产品摄影与商业影像。
温州大学数字媒体艺术 2027 届。

## 仓库结构

```
index.html                 站点唯一页面(数据驱动,作品目录内嵌在 JS 中)
assets/                    图片资源(已优化:大图 WebP 化,内嵌图外抽)
scripts/
  optimize-site.sh         优化流水线(幂等):base64 外抽 + 大图 WebP q92 + 引用重写
  deploy-portfolio.sh      服务器侧自动部署脚本(轮询 + 多镜像重试 + 原子发布 + 回滚)
.github/workflows/ci.yml   CI:资源引用完整性校验 + 体积体检
```

## 更新作品的流程

1. 往 `assets/` 加原图,在 `index.html` 的作品目录(JS 数据)里引用
2. 本地跑一次优化(幂等,可重复执行):
   ```bash
   scripts/optimize-site.sh        # 依赖 cwebp:brew install webp 或 apt install webp
   ```
3. 提交并推送 `main`。已配置自动部署的服务器会在 10 分钟内自行更新

## 自动部署(CD)原理

服务器上由 cron 定时执行 `scripts/deploy-portfolio.sh`:

- 轮询 `main` 最新 commit,SHA 变化才触发部署
- 国内访问 GitHub 不稳定:GitHub 元信息与 tarball 下载均走多镜像轮询(`gh-proxy.com` → `ghproxy.net` → `mirror.ghproxy.com` → `ghfast.top` → 直连),curl 自带重试
- 下载的 tar.gz 先做完整性校验,再重跑优化流水线,保证任何来源的提交上线前都被优化
- 原子发布:`webroot` 是指向 `releases/<sha>` 的符号链接,一次 `mv -T` 完成切换,请求无感知
- 部署后健康检查,失败自动回滚上一版本;保留最近 3 个版本
- 全程只读公开仓库,无需部署密钥,无需开放入站端口

服务器安装(一次性):

```bash
crontab -e
# */10 * * * * REPO_NAME=... SITE_DIR=... HEALTHCHECK_URL=https://你的地址/ ~/sites/deploy-portfolio.sh >> ~/sites/deploy.log 2>&1
```

## 性能

优化前后对比(实测):

| 指标 | 优化前 | 优化后 |
|---|---|---|
| index.html | 4.3 MB | ≈1.4 MB |
| 资源总量 | 430 MB | ≈108 MB |
| 最大单图 | 22 MB | 4.1 MB |

优化均为无损或视觉无损:base64 外抽字节不变;WebP q92 保留 ICC 色彩档案,肉眼不可分辨,原始终终保留在 git 历史中。
