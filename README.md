# Auxo16

Auxo 3 完整复刻到 iOS 16（最低 iOS 16.0）。

当前阶段：**探针 v1.0.0** —— 先摸清 iOS 16 上 Auxo3 依赖的私有类存亡与方法签名，
再开始写主体代码（约 5,200 行，8 个阶段 A-H）。

## 用 GitHub Actions 打包

push 到 `main` 会自动跑两个 job：

| job | Architecture | 安装路径 | 适用 |
|---|---|---|---|
| `roothide-off` | `iphoneos-arm64` | `/var/jb/Library/MobileSubstrate/DynamicLibraries/` | 常规 rootless（Dopamine 等） |
| `roothide-on` | `iphoneos-arm64e` | `/Library/MobileSubstrate/DynamicLibraries/` | **RootHide** |

两者 dylib 都是 FAT（arm64 + arm64e 双切片），功能完全相同，
区别只在 deb 的 `Architecture` 字段和安装前缀 —— 这是 RootHide 的装载约定。

## 装完做什么

1. 装包 → 重启 SpringBoard 或重启设备
2. 等 15 秒（探针延迟执行，避开启动关键期）
3. 取 `/var/mobile/Media/Auxo16-probe.txt`
4. 把文件内容回传

报告会列出 42 个类的存亡、41 个 selector 的归属类与完整签名、
以及切换器内部 `_appLayouts` / `_recents` / `_applicationsByBundleIdentifer` 的真实结构。

## 安全

探针只读不写，不改系统状态，不联网，不读 UDID。
所有动态调用都过 `respondsToSelector` + `@try`，
所有 ivar 读取都先查类型编码是否为对象类型。
最坏情况只是没有报告文件，不会崩溃。
