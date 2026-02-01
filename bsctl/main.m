
#include <Foundation/Foundation.h>
#include <roothide.h>
#include "commlib.h"
#include "libbsd.h"
#include "resign.h"
#include "jbclient.h"

static bool sendFakeMountRequest(const char *actionCStr, const char *pathCStr)
{
	if(strlen(pathCStr) == 0 || pathCStr[0] != '/') {
		fprintf(stderr, "invalid path\n");
		return false;
	}
	if(strlen(actionCStr) == 0) actionCStr = "mount";
	return jbclient_fake_mount_check(actionCStr, pathCStr);;
}


static int initFakeMountFiles(NSString *mountPath)
{
	if(mountPath.length == 0 || ![mountPath hasPrefix:@"/"]) {
		fprintf(stderr, "invalid path\n");
		return 1;
	}

	NSFileManager *fileManager = [NSFileManager defaultManager];
	if(![fileManager fileExistsAtPath:mountPath]) {
		fprintf(stderr, "source not exists: %s\n", mountPath.fileSystemRepresentation);
		return 2;
	}

	NSString *newPath = [jbroot(@"/mnt") stringByAppendingString:mountPath];
	BOOL isDir = NO;
	BOOL exists = [fileManager fileExistsAtPath:newPath isDirectory:&isDir];
	if(exists && !isDir) {
		fprintf(stderr, "destination exists but not dir: %s\n", newPath.fileSystemRepresentation);
		return 3;
	}

	bool needsInit = NO;
	if(!exists) {
		if(![fileManager createDirectoryAtPath:newPath withIntermediateDirectories:YES attributes:nil error:nil]) {
			fprintf(stderr, "mkdir failed: %s\n", newPath.fileSystemRepresentation);
			return 3;
		}
		needsInit = YES;
	} else {
		NSArray *contents = [fileManager contentsOfDirectoryAtPath:newPath error:nil];
		if(contents.count == 0) {
			needsInit = YES;
		}
	}

	if(needsInit) {
		NSString *tmpPath = [newPath stringByAppendingString:@"_tmp"]; // keep behavior consistent with app-side implementation
		[fileManager removeItemAtPath:tmpPath error:nil];
		if(![fileManager copyItemAtPath:mountPath toPath:tmpPath error:nil]) {
			fprintf(stderr, "copy failed: %s -> %s\n", mountPath.fileSystemRepresentation, tmpPath.fileSystemRepresentation);
			[fileManager removeItemAtPath:tmpPath error:nil];
			return 3;
		}
		[fileManager removeItemAtPath:newPath error:nil];
		if(![fileManager moveItemAtPath:tmpPath toPath:newPath error:nil]) {
			fprintf(stderr, "move failed: %s -> %s\n", tmpPath.fileSystemRepresentation, newPath.fileSystemRepresentation);
			[fileManager removeItemAtPath:tmpPath error:nil];
			return 3;
		}
	}

	NSString *wantsMountsPlistPath = jbroot(@"/mnt/zqbb_mounts.plist");
	NSMutableDictionary *wantsMountsDict = [NSMutableDictionary dictionaryWithContentsOfFile:wantsMountsPlistPath];
	if(!wantsMountsDict) wantsMountsDict = [NSMutableDictionary new];

	NSMutableArray *mountPaths = nil;
	id existing = wantsMountsDict[@"MountPaths"];
	if([existing isKindOfClass:[NSArray class]]) {
		mountPaths = [existing mutableCopy];
	}
	if(!mountPaths) mountPaths = [NSMutableArray new];

	if(![mountPaths containsObject:mountPath]) {
		[mountPaths addObject:mountPath];
	}
	wantsMountsDict[@"MountPaths"] = mountPaths;

	BOOL ok = [wantsMountsDict writeToFile:wantsMountsPlistPath atomically:YES];
	if(!ok) {
		fprintf(stderr, "plist write failed: %s\n", wantsMountsPlistPath.fileSystemRepresentation);
		return 4;
	}
	printf("ok\n");
	return 0;
}

static int removeFakeMountConfig(NSString *mountPath)
{
	if(mountPath.length == 0 || ![mountPath hasPrefix:@"/"]) {
		fprintf(stderr, "invalid path\n");
		return 1;
	}

	NSString *wantsMountsPlistPath = jbroot(@"/mnt/zqbb_mounts.plist");
	NSMutableDictionary *wantsMountsDict = [NSMutableDictionary dictionaryWithContentsOfFile:wantsMountsPlistPath];
	if(!wantsMountsDict) {
		// Nothing to remove.
		printf("ok\n");
		return 0;
	}

	NSMutableArray *mountPaths = nil;
	id existing = wantsMountsDict[@"MountPaths"];
	if([existing isKindOfClass:[NSArray class]]) {
		mountPaths = [existing mutableCopy];
	}
	if(!mountPaths) mountPaths = [NSMutableArray new];

	if([mountPaths containsObject:mountPath]) {
		[mountPaths removeObject:mountPath];
	}

	if(mountPaths.count == 0) {
		[[NSFileManager defaultManager] removeItemAtPath:wantsMountsPlistPath error:nil];
		printf("ok\n");
		return 0;
	}

	wantsMountsDict[@"MountPaths"] = mountPaths;
	BOOL ok = [wantsMountsDict writeToFile:wantsMountsPlistPath atomically:YES];
	if(!ok) {
		fprintf(stderr, "plist write failed: %s\n", wantsMountsPlistPath.fileSystemRepresentation);
		return 4;
	}
	printf("ok\n");
	return 0;
}

static int removeFakeMountFiles(NSString *mountPath)
{
	if(mountPath.length == 0 || ![mountPath hasPrefix:@"/"]) {
		fprintf(stderr, "invalid path\n");
		return 1;
	}

	NSString *targetPath = [jbroot(@"/mnt") stringByAppendingString:mountPath];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if(![fileManager fileExistsAtPath:targetPath]) {
		printf("path not exists, nothing to do\n");
		return 0;
	}

	NSError *error = nil;
	[fileManager removeItemAtPath:targetPath error:&error];
	if(error) {
		fprintf(stderr, "remove failed: %s\n", targetPath.fileSystemRepresentation);
		return 2;
	}
	printf("ok\n");
	return 0;
}

int jitest(int count, int time)
{
	for(int i=0; i<count; i++)
	{
		if(time) usleep(time);

		printf("test %d\n", i);

		assert(bsd_enableJIT() == 0);
	}

	return 0;
}

int main(int argc, char *argv[], char *envp[])
{
#ifdef ENABLE_LOGS
	FileLogDebug("bsctl started with environment variables:\n");
	for (char*const* env = environ; *env != 0; env++) {
		FileLogDebug("%s\n", *env);
	}
	FileLogDebug("bsctl started args:\n");
	for (int i = 0; i < argc; i++) {
		FileLogDebug("%s\n", argv[i]);
	}
#endif

	if(argc >= 2) 
	{
		if(strcmp(argv[1], "startup")==0)
		{
			int ret1 = spawn_bootstrap_binary((char*const[]){"/usr/bin/launchctl", "bootstrap", "system", "/Library/LaunchDaemons", NULL}, NULL, NULL);
			int ret2 = spawn_bootstrap_binary((char*const[]){"/usr/bin/uicache", "-a", NULL}, NULL, NULL);
			return (ret1==0 && ret2==0) ? 0 : -1;
		}
		else if(strcmp(argv[1], "initmount") == 0)
		{
			@autoreleasepool {
					if(argc < 3) {
						fprintf(stderr, "usage: bsctl initmount <path>\n");
						return 1;
					}
					
					NSString *mountPath = [NSString stringWithUTF8String:argv[2]];
					return initFakeMountFiles(mountPath);
			}
		}
		else if(strcmp(argv[1], "uninitmount") == 0)
		{
			@autoreleasepool {
				if(argc < 3) {
					fprintf(stderr, "usage: bsctl uninitmount <path>\n");
					return 1;
				}
				NSString *mountPath = [NSString stringWithUTF8String:argv[2]];
				return removeFakeMountConfig(mountPath);
			}
		}
		else if(strcmp(argv[1], "fakemount") == 0)
		{
			@autoreleasepool {
				if(argc < 4) {
					fprintf(stderr, "usage: bsctl fakemount <mount|unmount> <path>\n");
					return 1;
				}
				const char* actionCStr = argv[2];
				const char* pathCStr = argv[3];
				int result = sendFakeMountRequest(actionCStr, pathCStr) ? 0 : 2;
				return result;
			}
		}
		else if(strcmp(argv[1], "removeFakeMountFiles") == 0)
		{
			@autoreleasepool {
				if(argc < 3) {
					fprintf(stderr, "usage: bsctl removeFakeMountFiles <path>\n");
					return 1;
				}
				NSString *mountPath = [NSString stringWithUTF8String:argv[2]];
				return removeFakeMountFiles(mountPath);
			}
		}
		else if(strcmp(argv[1], "check") == 0)
		{
			int result=-1;
			FILE* fp = fopen(BSD_PID_PATH, "r");
			if(fp) {
				pid_t pid=0;
				fscanf(fp, "%d", &pid);
				printf("server pid=%d\n", pid);
				if(pid > 0) {
					result = kill(pid, 0);
					printf("server status=%d\n", result);
				}
				fclose(fp);
			} else {
				printf("server not running!\n");
			}
			return result;
		}
		else if(strcmp(argv[1], "stop") == 0)
		{
			return bsd_stopServer();
		}
		else if(strcmp(argv[1], "jitest") == 0)
		{
			int count=1; int time=0;
			if(argc >= 3) count = atoi(argv[2]);
			if(argc >= 4) time = atoi(argv[3]);
			jitest(count, time);
			printf("client return!\n");
			return 0;
		}
		else if(strcmp(argv[1], "usreboot") == 0)
		{
			int userspaceReboot(void);
			return userspaceReboot();
		}
		else if(strcmp(argv[1], "openssh") == 0)
		{
			ASSERT(argc >= 3);
			if(strcmp(argv[2],"start")==0) {
				return bsd_opensshctl(true);
			} else if(strcmp(argv[2],"stop")==0) {
				return bsd_opensshctl(false);
			} else if(strcmp(argv[2],"check")==0) {
				return bsd_opensshcheck();
			} else abort();
		}
		else if(strcmp(argv[1], "sbtoken") == 0)
		{
			const char* sbtoken = bsd_getsbtoken();
			printf("sbtoken=%s\n", sbtoken);
			if(sbtoken) free((void*)sbtoken);
			return sbtoken==NULL?-1:0;
		}
		else if(strcmp(argv[1], "resign") == 0)
		{
			bool resignAll = argc == 2 ? true : false;
			return ResignSystemExecutables(resignAll);
		}
	}

	printf("unknown command\n");
	return -1;
}
