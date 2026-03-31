<img width="1024" height="572" alt="image" src="https://github.com/user-attachments/assets/7fc75280-823c-4447-bbcd-57441791d6bc" />

# AutoTile

一个轻量的 macOS 菜单栏窗口整理工具，适合想快速整理窗口、快速显示桌面的人。

它专注做三件小而直接的事：

- `平铺窗口`：把当前屏幕上的窗口尽量均匀整理
- `显示桌面`：把当前屏幕窗口退下去，直接看到桌面
- `恢复上一次布局`：把窗口恢复到整理前的状态

## 一眼看懂

- 运行后常驻在菜单栏
- 点击菜单即可整理窗口
- 不依赖账号，不上传数据
- 默认本地运行，本地生效

## 适合谁

- 经常同时开很多窗口的人
- 想快速把桌面整理干净的人
- 不想装重型窗口管理器，只想要一个简单工具的人

## 当前功能

- 菜单栏常驻
- 支持多屏场景，优先处理当前窗口最多的那个屏幕
- 两窗口场景下优先做左右分栏
- 支持“显示桌面”后恢复布局
- 自动跳过：
  - 最小化窗口
  - 全屏窗口
  - 太小或不可控的系统窗口

## 安装

### 方式一：直接下载发布包

如果仓库已经提供发布包，下载 `AutoTile-macOS.zip` 后：

1. 解压
2. 把 `AutoTile.app` 拖到“应用程序”
3. 打开应用
4. 在 `系统设置 -> 隐私与安全性 -> 辅助功能` 中允许 `AutoTile`

### 方式二：本地构建后安装

```bash
cd AutoTile-GitHub
bash build.sh
bash install.sh
```

### 方式三：自己生成发布压缩包

```bash
cd AutoTile-GitHub
bash package_release.sh
```

生成文件：

`release/AutoTile-macOS.zip`

## 使用

1. 打开 `AutoTile.app`
2. 第一次运行时，去：
   `系统设置 -> 隐私与安全性 -> 辅助功能`
3. 允许 `AutoTile`
4. 回到菜单栏图标，使用：
   - `平铺窗口`
   - `显示桌面`
   - `恢复上一次布局`

## 隐私说明

- 不需要登录账号
- 不依赖云端服务
- 默认不上传任何窗口数据
- 默认不输出调试日志
- 只有在手动设置 `AUTOTILE_DEBUG=1` 时，才会写入临时调试日志

## 构建

```bash
cd AutoTile-GitHub
bash build.sh
```

构建完成后生成：

`dist/AutoTile.app`

## 打包发布

```bash
cd AutoTile-GitHub
bash package_release.sh
```

会生成：

`release/AutoTile-macOS.zip`

## 项目结构

```text
AutoTile-GitHub/
├── Sources/
├── build.sh
├── install.sh
├── package_release.sh
├── Info.plist
└── README.md
```

## 调试

只有在手动开启下面这个环境变量时，才会写临时调试日志：

```bash
AUTOTILE_DEBUG=1
```

## 说明

- 当前版本是轻量工具，不是完整的平铺式窗口管理器
- 当前版本以本地使用为主，不包含账号同步
- 如果后续要面向更广泛用户发布，建议再补正式签名和 notarization
