# GitHub 上传说明

这个项目已经整理成适合公开仓库的结构。

## 推荐上传内容

- `Sources/`
- `Info.plist`
- `build.sh`
- `install.sh`
- `package_release.sh`
- `.gitignore`
- `README.md`

## 不建议上传

- `dist/`
- `build/`
- `.build/`
- `output/`
- `release/`

这些目录已经在 `.gitignore` 里忽略。

## 本地发布准备文件夹

如果你只想快速找到打包好的文件，可以看：

`github-ready/`

里面会放：

- 源码压缩包
- 安装包压缩包
- 当前 README 副本
