#import <Foundation/Foundation.h>
#include <roothide.h>
#include "common.h"
#include <sys/mount.h>
#include <string.h>
#include <errno.h>

static int fakeMountOne(const char *mountPath)
{
    if (mountPath == NULL || mountPath[0] == '\0' || mountPath[0] != '/') {
        FileLogDebug("fakeMount: invalid mountPath");
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

int fakeMount(const char* mountAction, const char* path)
{
    if (mountAction == NULL || path == NULL) {
        FileLogDebug("fakeMount: invalid args");
        return 1;
    }

    if (strcmp(mountAction, "mount") == 0) {
        return fakeMountOne(path);
    } else if (strcmp(mountAction, "unmount") == 0) {
        return fakeUnmountOne(path);
    } else {
        FileLogDebug("fakeMount: unknown mountAction %s", mountAction);
        return 1;
    }
}

void fakeMountsWorker(void)
{
    @autoreleasepool {
        // 从jbroot(@"/mnt/zqbb_mounts.plist")读取需要mount的路径列表
        FileLogDebug("launchdhook starting fake mounts");
        NSString *wantsMountsPlistPath = jbroot(@"/mnt/zqbb_mounts.plist");
        if (![[NSFileManager defaultManager] fileExistsAtPath:wantsMountsPlistPath]) {
            return;
        }
        NSDictionary *wantsMountsDict = [NSDictionary dictionaryWithContentsOfFile:wantsMountsPlistPath];
        NSArray *mountPaths = wantsMountsDict[@"MountPaths"];

        if ([mountPaths isKindOfClass:[NSArray class]]) {
            for (id mountPath in mountPaths) {
                if ([mountPath isKindOfClass:[NSString class]]) {
                    NSString *mountPathStr = (NSString *)mountPath;
                    fakeMount("mount", mountPathStr.UTF8String);
                }
            }
        } else {
            FileLogDebug("launchdhook: no MountPaths in %s", wantsMountsPlistPath.UTF8String);
        }
        FileLogDebug("launchdhook finished fake mounts");
    }
}