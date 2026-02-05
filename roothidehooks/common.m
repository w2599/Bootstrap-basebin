#import <Foundation/Foundation.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <roothide.h>
#include <sys/mount.h>
#include "common.h"

bool isAppleBundlePath(const char* path)
{
	//no path? may be a system bundle
	if(!path) return true;
	NSLog(@"[----]isAppleBundlePath: %s", path);

	// read Info.plist
	NSString* infoPlistPath = [NSString stringWithFormat:@"%s/Info.plist", path];
	NSDictionary* infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
	if([[infoPlist objectForKey:@"CFBundleIdentifier"] hasPrefix:@"com.apple."]){
		return true;
	}
	return false;
}

bool isJailbreakBundlePath(const char* path)
{
	//no path? may be a system bundle
	if(!path) return false;

	struct statfs fs;
	if(statfs(path, &fs) != 0)
	{
		//path not exists, may be a jailbreak bundle
		return true;
	}

	if(strcmp(fs.f_mntonname, "/") == 0) {
		// anything on rootfs is not jailbreak stuffs
		return false;
	}

	if (isAppleBundlePath(path)) {
		// apple bundle is not jailbreak stuffs
		return false;
	}

	if(isRemovableBundlePath(path))
	{
		if(!hasTrollstoreMarker(path)) {
			// normal app bundle
			return false;
		}
	}

	return true;
}
