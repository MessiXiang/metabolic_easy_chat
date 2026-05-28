# 自动更新发布配置

本项目使用 Sparkle + GitHub Actions + GitHub Releases + GitHub Pages 提供 App 内更新。

## GitHub Secrets

在仓库 `Settings > Secrets and variables > Actions` 中配置：

- `SPARKLE_PUBLIC_ED_KEY`：Sparkle 公钥，构建时写入 App 的 Info.plist。
- `SPARKLE_PRIVATE_ED_KEY`：Sparkle 私钥，GitHub Actions 用它签名更新包。

可在本地用 Sparkle 的 `generate_keys` 生成密钥对。私钥只放到 GitHub Secrets，不要提交到仓库。

## 更新流程

1. PR 合并到 `main`。
2. `.github/workflows/release-app.yml` 自动构建 `metabolic_easy_chat.app`。
3. workflow 上传 `metabolic_easy_chat.zip` 到 `latest` Release。
4. workflow 生成并部署 `docs/appcast.xml` 到 GitHub Pages。
5. App 内点击 `Settings > Updates > 检查更新`。

更新源：

```text
https://messixiang.github.io/metabolic_easy_chat/appcast.xml
```

## 注意

当前 workflow 为方便自动构建关闭了代码签名。如果需要给其他机器稳定分发，建议改为 Developer ID 签名并 notarize。Sparkle 的更新包签名仍然应保持启用。
