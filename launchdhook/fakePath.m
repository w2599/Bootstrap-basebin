#import <Foundation/Foundation.h>
#include <roothide.h>
#include "common.h"
#include <sys/mount.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

static const NSUInteger kMaxFakeMountPaths = 64;

static int fakeMountOne(const char *mountPath)
{
    if (mountPath == NULL || mountPath[0] == '\0' || mountPath[0] != '/') {
        FileLogDebug("fakeMount: invalid mountPath");
        return 1;
    }

    if (access(mountPath, F_OK) != 0) {
        FileLogDebug("fakeMount: mountPath not exists %s", mountPath);
        return 1;
    }

    // 查一下有没有挂载过了
    struct statfs fsinfo = {};
    if (statfs(mountPath, &fsinfo) == 0) {
        if (strcmp(fsinfo.f_fstypename, "bindfs") == 0) {
            FileLogDebug("fakeMount: %s already mounted", mountPath);
            return 0;
        }
    }

    NSString *newPathStr = [NSString stringWithFormat:@"%s%s", jbroot("/mnt"), mountPath];
    const char *newPath = newPathStr.UTF8String;

        if (access(newPath, F_OK) != 0) {
            FileLogDebug("fakeMount: source path not exists %s", newPath);
            return 1;
        }

    int ret = mount("bindfs", mountPath, MNT_RDONLY, (void *)newPath);
    if (ret == 0) {
        FileLogDebug("fakeMount: mounted %s to %s", newPath, mountPath);
        return 0;
    } else {
        FileLogDebug("fakeMount: mount %s to %s failed: %s", newPath, mountPath, strerror(errno));
        return 1;
    }
}

static int fakeUnmountOne(const char *mountPath)
{
    if (mountPath == NULL || mountPath[0] == '\0' || mountPath[0] != '/') {
        FileLogDebug("fakeUnmount: invalid mountPath");
        return 1;
    }

    int ret = unmount(mountPath, MNT_FORCE);
    if (ret == 0) {
        FileLogDebug("fakeUnmount: unmounted %s", mountPath);
        return 0;
    } else {
        FileLogDebug("fakeUnmount: unmount %s failed: %s", mountPath, strerror(errno));
        return 1;
    }
}

int fakeMountAction(const char* mountAction, const char* path)
{
    if (mountAction == NULL || path == NULL) {
        FileLogDebug("fakeMountAction: invalid args");
        return 1;
    }

    if (strcmp(mountAction, "mount") == 0) {
        return fakeMountOne(path);
    } else if (strcmp(mountAction, "unmount") == 0) {
        return fakeUnmountOne(path);
    } else {
        FileLogDebug("fakeMountAction: unknown mountAction %s", mountAction);
        return 1;
    }
}

void fakeMountsWorker(void)
{
    @autoreleasepool {
        @try {
            FileLogDebug("launchdhook starting fake mounts");
            NSString *wantsMountsPlistPath = jbroot(@"/mnt/zqbb_mounts.plist");
            if (access(wantsMountsPlistPath.UTF8String, F_OK) != 0) {
                FileLogDebug("launchdhook: mounts plist not found %s", wantsMountsPlistPath.UTF8String);
                return;
            }

            NSDictionary *wantsMountsDict = [NSDictionary dictionaryWithContentsOfFile:wantsMountsPlistPath];
            if (![wantsMountsDict isKindOfClass:[NSDictionary class]]) {
                FileLogDebug("launchdhook: invalid mounts plist %s", wantsMountsPlistPath.UTF8String);
                return;
            }

            NSArray *mountPaths = wantsMountsDict[@"MountPaths"];
            if (![mountPaths isKindOfClass:[NSArray class]]) {
                FileLogDebug("launchdhook: no MountPaths in %s", wantsMountsPlistPath.UTF8String);
                return;
            }

            NSUInteger count = MIN(mountPaths.count, kMaxFakeMountPaths);
            if (mountPaths.count > kMaxFakeMountPaths) {
                FileLogDebug("launchdhook: MountPaths too many (%lu), truncate to %lu", (unsigned long)mountPaths.count, (unsigned long)kMaxFakeMountPaths);
            }

            for (NSUInteger i = 0; i < count; i++) {
                id mountPath = mountPaths[i];
                if (![mountPath isKindOfClass:[NSString class]]) {
                    continue;
                }

                NSString *mountPathStr = (NSString *)mountPath;
                if (mountPathStr.length == 0 || ![mountPathStr hasPrefix:@"/"]) {
                    continue;
                }

                fakeMountAction("mount", mountPathStr.UTF8String);
            }

            FileLogDebug("launchdhook finished fake mounts");
        }
        @catch (NSException *exception) {
            FileLogError("launchdhook fake mounts exception: %s", exception.reason.UTF8String ?: "unknown");
        }
    }
}