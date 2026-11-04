//
//  Auxo16Probe.m
//  Auxo 3 -> iOS 16 复刻工程 · 真机类/方法/ivar 探针
//
//  设计原则：零私有头文件依赖。
//  只用 objc/runtime.h + Foundation + UIKit 公开 API，
//  因此可以被任何 iOS 版本加载，不需要为每个系统版本维护一套头。
//
//  产出：/var/mobile/Media/Auxo16-probe.txt
//
//  Author: RNA for ganjibamao
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/utsname.h>

#pragma mark - 输出缓冲

static NSMutableString *gOut = nil;

static void P(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    [gOut appendString:s];
    [gOut appendString:@"\n"];
}

static void PSection(NSString *title) {
    P(@"");
    P(@"==================================================================");
    P(@"  %@", title);
    P(@"==================================================================");
}

#pragma mark - 探测目标清单
//
// 每个条目：{ 类名, 说明 }
// 说明只用于报告可读性，不影响探测。

typedef struct { const char *cls; const char *note; } ProbeTarget;

static const ProbeTarget kTargets[] = {
    // ---- 切换器核心 ----
    { "SBFluidSwitcherViewController",      "切换器主 VC（iOS16 核心）" },
    { "SBMainSwitcherControllerCoordinator","切换器协调器，持有 _appLayouts" },
    { "SBSwitcherController",               "切换器控制器" },
    { "SBAppSwitcherModel",                 "任务模型，持有 _recents" },
    { "SBAppLayout",                        "应用布局" },
    { "SBDisplayItem",                      "显示条目" },
    { "SBFluidSwitcherItemContainer",       "单个卡片容器" },
    { "SBFluidSwitcherGestureManager",      "切换器手势管理" },
    { "SBFluidSwitcherRootSwitcherModifier","modifier 根节点" },
    { "SBAppSwitcherPageView",              "卡片页面视图" },

    // ---- 应用 ----
    { "SBApplicationController",            "应用控制器，_applicationsByBundleIdentifer" },
    { "SBApplication",                      "单个应用对象" },
    { "SBUIController",                     "UI 控制器（iOS16 仍在）" },
    { "SBWorkspace",                        "工作区（iOS16 退化）" },
    { "SBSceneManagerCoordinator",          "场景协调" },
    { "SBMainWorkspace",                    "主工作区" },
    { "SBLockScreenManager",                "锁屏管理" },

    // ---- Control Center ----
    { "SBControlCenterController",          "CC 控制器" },
    { "SBControlCenterWindow",              "CC 窗口" },
    { "CCUIModularControlCenterOverlayViewController", "CC 模块化容器" },
    { "CCUIModuleInstanceManager",          "CC 模块实例管理" },

    // ---- 图标 ----
    { "SBIconController",                   "图标控制器" },
    { "SBIconModel",                        "图标模型" },
    { "SBIconView",                         "图标视图（SpringBoardHome）" },
    { "SBIconListView",                     "图标列表视图" },
    { "SBIcon",                             "图标基类" },
    { "SBIconListModel",                    "图标列表模型" },

    // ---- 媒体 ----
    { "MRUNowPlayingController",            "正在播放控制器（iOS16）" },
    { "MRUNowPlayingInfo",                  "正在播放信息" },
    { "SBMediaController",                  "媒体控制器（仍在）" },
    { "MRNowPlayingController",             "MediaRemote 控制器" },

    // ---- 音量/亮度 ----
    { "SBVolumeControl",                    "音量控制" },
    { "SBBacklightController",              "背光控制" },
    { "SBRingerControl",                    "铃声控制" },
    { "SBElasticSliderView",                "弹性滑块（iOS16 CC）" },

    // ---- 手势 ----
    { "SBSystemGestureManager",             "系统手势管理" },
    { "SBScreenEdgePanGestureRecognizer",   "屏幕边缘 pan" },
    { "SBHomeGesturePanGestureRecognizer",  "Home 手势 pan" },
    { "SBFluidSwitcherPanGestureRecognizer","切换器 pan" },
    { "SBOffscreenSwipeGestureRecognizer",  "Auxo3 依赖（预期已死）" },

    // ---- HUD / 其它 ----
    { "SBHUDController",                    "HUD 控制器" },
    { "SBRingerHUDController",              "铃声 HUD（Auxo3 依赖）" },
    { "SBApplicationIcon",                  "应用图标" },

    // ---- 设置页 ----
    { "PSListController",                   "设置页基类" },
    { "PSSpecifier",                        "设置项" },
};

// Auxo3 用到的、需要在 iOS16 上确认是否还存在的 selector
static const char *kSelectors[] = {
    // 切换器
    "setOffsetToIndex:animated:completion:",
    "normalizedOffsetOfIndex:",
    "currentPage",
    "pageController",
    "iconController",
    "switcherController",
    "contentView",
    "pageView",
    "iconView",
    "displayLayouts",
    // 应用
    "applicationsByBundleIdentifer",
    "allApplications",
    "bundleIdentifier",
    "displayName",
    "iconImage",
    "activateApplication:withResult:",
    "terminateApplication:",
    "killApplication:",
    "uninstallApplication:forReason:",
    "_applicationsByBundleIdentifer",
    "sharedInstance",
    // 手势
    "allowSystemGestureType:atLocation:",
    "handleShowControlCenterSystemGesture:",
    "isAppSwitcherShowing",
    "clickedMenuButton",
    "handleMenuDoubleTap",
    // CC
    "presentControlCenterForGestureRecognizer:",
    "dismissControlCenterAnimated:",
    "_modulesByID",
    // 媒体
    "togglePlayPause",
    "nextTrack",
    "previousTrack",
    "nowPlayingInfo",
    "title",
    "artist",
    "artworkImage",
    // 音量亮度
    "_setBacklightLevel:fromSource:forReason:",
    "_setMediaVolume:showHUD:",
    "setRingerVolume:",
    // 通用
    "init",
    "sharedInstance",
};

#pragma mark - 探测工具

// 递归 dump 方法（含父类），限制深度避免打印 NSObject 一大堆
static void DumpMethods(Class cls, NSString *label, BOOL includeInherited) {
    if (!cls) return;
    unsigned int count = 0;

    Method *list = class_copyMethodList(cls, &count);
    P(@"  -- %@ 的自身方法 (%u) --", label, count);
    if (count == 0) P(@"     (无)");
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(list[i]);
        const char *types = method_getTypeEncoding(list[i]);
        P(@"     %-58s  %s", sel_getName(sel), types ? types : "");
    }
    free(list);

    if (includeInherited) {
        Class sup = class_getSuperclass(cls);
        int depth = 0;
        while (sup && sup != [NSObject class] && depth < 4) {
            unsigned int c2 = 0;
            Method *m2 = class_copyMethodList(sup, &c2);
            P(@"  -- 继承自 %@ (%u) --", NSStringFromClass(sup), c2);
            for (unsigned int i = 0; i < c2 && i < 200; i++) {
                SEL sel = method_getName(m2[i]);
                const char *types = method_getTypeEncoding(m2[i]);
                P(@"     %-58s  %s", sel_getName(sel), types ? types : "");
            }
            free(m2);
            sup = class_getSuperclass(sup);
            depth++;
        }
    }
}

static void DumpIvars(Class cls) {
    if (!cls) return;
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    P(@"  -- ivar (%u) --", count);
    if (count == 0) P(@"     (无)");
    for (unsigned int i = 0; i < count; i++) {
        const char *name = ivar_getName(ivars[i]);
        const char *type = ivar_getTypeEncoding(ivars[i]);
        P(@"     %-52s  %s", name ? name : "?", type ? type : "");
    }
    free(ivars);
}

static void DumpProperties(Class cls) {
    if (!cls) return;
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(cls, &count);
    if (count == 0) { P(@"  -- property (0) --"); return; }
    P(@"  -- property (%u) --", count);
    for (unsigned int i = 0; i < count; i++) {
        const char *name = property_getName(props[i]);
        const char *attrs = property_getAttributes(props[i]);
        P(@"     %-52s  %s", name ? name : "?", attrs ? attrs : "");
    }
    free(props);
}

// 在类及其父类链上找 selector，返回定义所在类名
static NSString *FindSelector(Class cls, const char *selName) {
    if (!cls || !selName) return nil;
    SEL sel = sel_registerName(selName);
    Class cur = cls;
    int depth = 0;
    while (cur && depth < 8) {
        if (class_getInstanceMethod(cur, sel)) {
            const char *types = method_getTypeEncoding(class_getInstanceMethod(cur, sel));
            return [NSString stringWithFormat:@"%@  [%s]", NSStringFromClass(cur), types ? types : ""];
        }
        cur = class_getSuperclass(cur);
        depth++;
    }
    return nil;
}


#pragma mark - 安全调用（防 SpringBoard 崩溃）

// 只在类确实响应 selector 时才发消息。发错 selector 会抛 unrecognized selector，
// 在 SpringBoard 里等于自杀，所以一律先检查。
// 读 ivar 前先确认它是对象类型（编码以 @ 开头）。
// 若 ivar 是 int/float/结构体，object_getIvar 会崩。
static id SafeIvar(id obj, const char *name) {
    if (!obj || !name) return nil;
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return nil;
    const char *type = ivar_getTypeEncoding(iv);
    if (!type || type[0] != '@') return nil;
    @try {
        return object_getIvar(obj, iv);
    } @catch (NSException *e) {
        return nil;
    }
}

static id SafeMsg(id obj, const char *selName) {
    if (!obj || !selName) return nil;
    SEL sel = sel_registerName(selName);
    if (![obj respondsToSelector:sel]) return nil;
    @try {
        return ((id(*)(id,SEL))objc_msgSend)(obj, sel);
    } @catch (NSException *e) {
        return nil;
    }
}

static id SafeClassMsg(Class cls, const char *selName) {
    if (!cls || !selName) return nil;
    SEL sel = sel_registerName(selName);
    if (![cls respondsToSelector:sel]) return nil;
    @try {
        return ((id(*)(id,SEL))objc_msgSend)((id)cls, sel);
    } @catch (NSException *e) {
        return nil;
    }
}

#pragma mark - 环境信息

static NSString *DeviceIdentifier(void) {
    struct utsname u;
    if (uname(&u) == 0) return @(u.machine);
    return @"?";
}

static void DumpEnvironment(void) {
    PSection(@"环境信息");
    P(@"系统版本      : %@", [UIDevice currentDevice].systemVersion);
    P(@"设备型号      : %@", DeviceIdentifier());
    P(@"设备名称      : %@", [UIDevice currentDevice].name);
    P(@"UIKit 版本    : %@", NSStringFromClass([UIApplication class]));
    P(@"进程名        : %@", [NSProcessInfo processInfo].processName);
    P(@"进程 PID      : %d", [NSProcessInfo processInfo].processIdentifier);

    // 已加载的镜像（找私有框架）
    P(@"");
    P(@"已加载的相关镜像:");
    uint32_t count = _dyld_image_count();
    NSArray *keys = @[@"SpringBoard", @"SpringBoardHome", @"MediaControls",
                      @"ControlCenterUI", @"ControlCenterUIKit", @"MediaRemote",
                      @"BackBoard", @"Preferences"];
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *n = @(name);
        for (NSString *k in keys) {
            if ([n containsString:k]) { P(@"   %@", n); break; }
        }
    }

    // 屏幕几何
    UIWindow *win = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w.isKeyWindow) { win = w; break; }
        }
    }
    P(@"");
    if (win) {
        P(@"窗口尺寸      : %.1f x %.1f", win.bounds.size.width, win.bounds.size.height);
        P(@"安全区        : top=%.1f left=%.1f bottom=%.1f right=%.1f",
          win.safeAreaInsets.top, win.safeAreaInsets.left,
          win.safeAreaInsets.bottom, win.safeAreaInsets.right);
        P(@"scale         : %.1f", win.screen.scale);
        P(@"窗口数量      : %lu", (unsigned long)win.windowScene.windows.count);
    } else {
        P(@"窗口          : 未取到 keyWindow");
    }
}

#pragma mark - 主探测

static void ProbeClasses(void) {
    PSection(@"类存在性 + 方法 / ivar 全量 dump");

    int alive = 0, dead = 0;
    NSMutableArray *deadList = [NSMutableArray array];

    for (size_t i = 0; i < sizeof(kTargets) / sizeof(kTargets[0]); i++) {
        const char *name = kTargets[i].cls;
        const char *note = kTargets[i].note;

        @try {
            Class cls = objc_getClass(name);
            if (!cls) {
                dead++;
                [deadList addObject:@(name)];
                P(@"");
                P(@"### %@  →  ❌ 不存在   (%@)", @(name), @(note));
                continue;
            }
            alive++;
            P(@"");
            P(@"### %@  →  ✅ 存在   (%@)", @(name), @(note));
            P(@"     父类: %@", class_getSuperclass(cls) ? NSStringFromClass(class_getSuperclass(cls)) : @"(root)");
            DumpMethods(cls, @"实例方法", NO);
            DumpIvars(cls);
            DumpProperties(cls);
        } @catch (NSException *e) {
            P(@"### %@  dump 异常: %@", @(name), e.reason);
        }
    }

    P(@"");
    P(@"-------------------------------------------");
    P(@"存活 %d / 不存在 %d / 共 %zu", alive, dead, sizeof(kTargets)/sizeof(kTargets[0]));
    P(@"不存在的类: %@", [deadList componentsJoinedByString:@", "]);
}

static void ProbeSelectors(void) {
    PSection(@"关键 selector 定位（在哪个类上、签名是什么）");

    // 每个 selector 在哪些目标类上能找到
    for (size_t s = 0; s < sizeof(kSelectors)/sizeof(kSelectors[0]); s++) {
        const char *selName = kSelectors[s];
        NSMutableArray *hits = [NSMutableArray array];

        for (size_t i = 0; i < sizeof(kTargets)/sizeof(kTargets[0]); i++) {
            @try {
                Class cls = objc_getClass(kTargets[i].cls);
                if (!cls) continue;
                NSString *found = FindSelector(cls, selName);
                if (found) {
                    [hits addObject:[NSString stringWithFormat:@"%@ -> %@",
                                     @(kTargets[i].cls), found]];
                }
            } @catch (NSException *e) { }
        }

        if (hits.count) {
            P(@"");
            P(@"[✓] %s", selName);
            for (NSString *h in hits) P(@"      %@", h);
        } else {
            P(@"");
            P(@"[✗] %s   (目标类里都没找到)", selName);
        }
    }
}

static void ProbeSwitcherInternals(void) {
    PSection(@"切换器内部结构（实际取对象、看 ivar 值）");

    @try {
        // SBMainSwitcherControllerCoordinator
        Class coordCls = objc_getClass("SBMainSwitcherControllerCoordinator");
        if (coordCls) {
            id coord = SafeClassMsg(coordCls, "sharedInstance");
            P(@"SBMainSwitcherControllerCoordinator.sharedInstance = %@", coord ? coord : @"nil");
            if (coord) {
                Ivar iv = class_getInstanceVariable([coord class], "_appLayouts");
                if (iv) {
                    id layouts = SafeIvar(coord, "_appLayouts");
                    P(@"   _appLayouts = %@ (count=%lu)", layouts ? NSStringFromClass([layouts class]) : @"nil",
                      (unsigned long)[layouts respondsToSelector:@selector(count)] ? [layouts count] : 0);
                } else {
                    P(@"   _appLayouts ivar 不存在");
                }
            }
        }

        // SBAppSwitcherModel
        Class modelCls = objc_getClass("SBAppSwitcherModel");
        if (modelCls) {
            id model = SafeClassMsg(modelCls, "sharedInstance");
            P(@"");
            P(@"SBAppSwitcherModel.sharedInstance = %@", model ? model : @"nil");
            if (model) {
                Ivar iv = class_getInstanceVariable([model class], "_recents");
                if (iv) {
                    id recents = SafeIvar(model, "_recents");
                    P(@"   _recents = %@ (count=%lu)", recents ? NSStringFromClass([recents class]) : @"nil",
                      (unsigned long)[recents respondsToSelector:@selector(count)] ? [recents count] : 0);
                    if ([recents isKindOfClass:[NSArray class]]) {
                        int n = 0;
                        for (id item in recents) {
                            if (n++ >= 5) break;
                            P(@"      [%d] %@  ivars:", n-1, NSStringFromClass([item class]));
                            unsigned int ic = 0;
                            Ivar *ivs = class_copyIvarList([item class], &ic);
                            for (unsigned int k = 0; k < ic && k < 8; k++) {
                                P(@"           %s", ivar_getName(ivs[k]));
                            }
                            free(ivs);
                        }
                    }
                }
            }
        }

        // SBApplicationController
        Class appCls = objc_getClass("SBApplicationController");
        if (appCls) {
            id ctrl = SafeClassMsg(appCls, "sharedInstance");
            P(@"");
            P(@"SBApplicationController.sharedInstance = %@", ctrl ? ctrl : @"nil");
            if (ctrl) {
                Ivar iv = class_getInstanceVariable([ctrl class], "_applicationsByBundleIdentifer");
                if (iv) {
                    NSDictionary *d = SafeIvar(ctrl, "_applicationsByBundleIdentifer");
                    P(@"   _applicationsByBundleIdentifer count = %lu",
                      (unsigned long)([d isKindOfClass:[NSDictionary class]] ? d.count : 0));
                    if ([d isKindOfClass:[NSDictionary class]]) {
                        NSArray *keys = [d.allKeys sortedArrayUsingSelector:@selector(compare:)];
                        int n = 0;
                        for (NSString *k in keys) {
                            if (n++ >= 10) { P(@"      ... 共 %lu 个", (unsigned long)d.count); break; }
                            id app = d[k];
                            P(@"      %-42@  %@", k, NSStringFromClass([app class]));
                        }
                    }
                } else {
                    P(@"   _applicationsByBundleIdentifer ivar 不存在");
                }
            }
        }

        // SBFluidSwitcherViewController 实例（从协调器找）
        Class fluidCls = objc_getClass("SBFluidSwitcherViewController");
        P(@"");
        P(@"SBFluidSwitcherViewController 类 = %@", fluidCls ? @"存在" : @"不存在");

    } @catch (NSException *e) {
        P(@"切换器内部探测异常: %@", e.reason);
    }
}

static void ProbeIcons(void) {
    PSection(@"图标体系（SBIconController / SBIconView）");

    @try {
        Class icCls = objc_getClass("SBIconController");
        if (icCls) {
            id ic = SafeClassMsg(icCls, "sharedInstance");
            P(@"SBIconController.sharedInstance = %@", ic ? ic : @"nil");
            if (ic) {
                // 找 model
                Ivar iv = class_getInstanceVariable([ic class], "_model");
                if (!iv) iv = class_getInstanceVariable([ic class], "_iconModel");
                if (iv) {
                    id model = SafeIvar(ic, ivar_getName(iv));
                    P(@"   model ivar (%s) = %@", ivar_getName(iv), model ? NSStringFromClass([model class]) : @"nil");
                    if (model) {
                        unsigned int mc = 0;
                        Method *ms = class_copyMethodList([model class], &mc);
                        P(@"   model 方法里含 'icon' 的:");
                        for (unsigned int i = 0; i < mc; i++) {
                            const char *sn = sel_getName(method_getName(ms[i]));
                            if (strstr(sn, "icon") || strstr(sn, "Icon")) {
                                P(@"      %s", sn);
                            }
                        }
                        free(ms);
                    }
                }
            }
        }
    } @catch (NSException *e) {
        P(@"图标探测异常: %@", e.reason);
    }
}

static void ProbeMedia(void) {
    PSection(@"媒体（MRUNowPlayingController）");

    @try {
        Class c = objc_getClass("MRUNowPlayingController");
        if (c) {
            id ctrl = SafeMsg([c alloc], "init");
            P(@"MRUNowPlayingController alloc/init = %@", ctrl ? ctrl : @"nil");
        }
        Class mc = objc_getClass("SBMediaController");
        if (mc) {
            id m = SafeClassMsg(mc, "sharedInstance");
            P(@"SBMediaController.sharedInstance = %@", m ? m : @"nil");
            if (m) {
                P(@"   nowPlayingInfo = %@", SafeMsg(m, "nowPlayingInfo"));
            }
        }
    } @catch (NSException *e) {
        P(@"媒体探测异常: %@", e.reason);
    }
}

#pragma mark - 落盘

static NSArray<NSString *> *CandidatePaths(void) {
    return @[
        @"/var/mobile/Media/Auxo16-probe.txt",
        @"/var/mobile/Documents/Auxo16-probe.txt",
        @"/tmp/Auxo16-probe.txt",
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"Auxo16-probe.txt"],
    ];
}

static void WriteReport(void) {
    NSData *data = [gOut dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray *written = [NSMutableArray array];

    for (NSString *path in CandidatePaths()) {
        NSString *dir = [path stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil error:nil];
        NSError *err = nil;
        BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:&err];
        if (ok) {
            [written addObject:path];
            // 也放开权限，方便 Filza / SSH 直接读
            [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644}
                                             ofItemAtPath:path error:nil];
        }
    }

    NSLog(@"[Auxo16Probe] report written to: %@", written);
}

#pragma mark - 入口

static void Auxo16ProbeRun(void) {
    gOut = [NSMutableString string];

    P(@"Auxo 3 → iOS 16 复刻工程 · 真机探针");
    P(@"生成时间: %@", [NSDate date]);
    P(@"探针版本: 1.0");

    @try {
        DumpEnvironment();
        ProbeClasses();
        ProbeSelectors();
        ProbeSwitcherInternals();
        ProbeIcons();
        ProbeMedia();
    } @catch (NSException *e) {
        P(@"");
        P(@"!!! 顶层异常: %@  %@", e.name, e.reason);
    }

    P(@"");
    P(@"================== 探测结束 ==================");
    P(@"报告行数: %lu", (unsigned long)[gOut componentsSeparatedByString:@"\n"].count);

    WriteReport();

    NSLog(@"[Auxo16Probe] done, %lu lines", (unsigned long)[gOut componentsSeparatedByString:@"\n"].count);
}

// 延迟到 SpringBoard 完成启动后再跑：
// constructor 时机太早，UIApplication.connectedScenes 可能还没建立，
// 直接在里面访问 UIKit 会导致 SpringBoard 启动崩溃循环。
__attribute__((constructor))
static void Auxo16ProbeInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @try {
            Auxo16ProbeRun();
        } @catch (NSException *e) {
            NSLog(@"[Auxo16Probe] FATAL: %@ %@", e.name, e.reason);
        }
    });
}
