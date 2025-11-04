#import <Foundation/Foundation.h>

#include "kern_memorystatus.h"
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <pwd.h>
#include <libgen.h>

#ifdef KDEBUG
#define JetLog(fmt, ...) NSLog((@"[Kids] <Jetsam> " fmt), ##__VA_ARGS__)
#else
#define JetLog(...) (void)0
#endif

int setHighWaterMark(int pid, int limit) {
    int cmd = MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK;
    int result = memorystatus_control(cmd, pid, limit, 0, 0);
    if (result) {
        fprintf(stderr, "[Kids] failed to setHighWaterMark of pid %d to %dMB: %d\n", pid, limit, errno);
    }
    return result;
}

int getHightWaterMark(int pid) {
    int size = memorystatus_control(MEMORYSTATUS_CMD_GET_PRIORITY_LIST, 0, 0, NULL, 0);
    if (size < 0) {
        fprintf(stderr, "[Kids] failed to get priority list size: %d\n", errno);
        return -1;
    }

    memorystatus_priority_entry_t *list = (memorystatus_priority_entry_t *)malloc(size);
    if (!list) {
        fprintf(stderr, "[Kids] failed to allocate memory of size %d: %d\n", size, errno);
        return -1;
    }

    size = memorystatus_control(MEMORYSTATUS_CMD_GET_PRIORITY_LIST, 0, 0, list, size);
    int count = size / sizeof(memorystatus_priority_entry_t);
    for (int i = 0; i < count; ++i) {
        memorystatus_priority_entry_t *entry = list + i;
        if (entry->pid == pid) return entry->limit;
    }
    return -1;
}

#import "CrossOverIPC.h"

NS_ASSUME_NONNULL_BEGIN

@interface JetsamManager : NSObject

+ (instancetype)sharedManager;
- (void)startListening;
- (void)stopListening;

@end

NS_ASSUME_NONNULL_END

@implementation JetsamManager {
    CrossOverIPC *_cross;
    NSString *_centerName;
}

+ (instancetype)sharedManager {
    static JetsamManager *gInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gInstance = [[JetsamManager alloc] initPrivate];
    });
    return gInstance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
    }
    return self;
}

- (void)startListening {
    static dispatch_once_t onceToken1;
    dispatch_once(&onceToken1, ^{ 
        // centerNamed:type: giả sử trả về singleton center
        _cross = [objc_getClass("CrossOverIPC") centerNamed:@"com.kids.jetsamlisten" type:SERVICE_TYPE_LISTENER];
        if (!_cross) {
            JetLog(@"<Jetsam> Failed obtain CrossOverIPC center: com.kids.jetsamlisten");
            return;
        }

        [_cross registerForMessageName:@"gettingHighWaterMark" target:self selector:@selector(handleGettingHighWaterMark:withUserInfo:)];
        [_cross registerForMessageName:@"setupHighWaterMark" target:self selector:@selector(handleSetupHighWaterMark:withUserInfo:)];
        [_cross registerForMessageName:@"setupPriority" target:self selector:@selector(handleSetupPriority:withUserInfo:)];

        JetLog(@"<Jetsam> Listening on com.kids.jetsamlisten");
    });
}

- (void)stopListening {
    if (!_cross) return;
    // Nếu CrossOverIPC có method để unregister, gọi ở đây.
    // [_cross unregisterForMessageName:...];
    _cross = nil;
    JetLog(@"<Jetsam> Stopped listening");
}

#pragma mark - Helpers for memorystatus

- (int)getHighWaterMarkForPid:(int)pid {
    // Lấy danh sách priority (size đầu tiên)
    int size = memorystatus_control(MEMORYSTATUS_CMD_GET_PRIORITY_LIST, 0, 0, NULL, 0);
    if (size < 0) {
        JetLog(@"<Jetsam> memorystatus_control size failed: %d (errno=%d)", size, errno);
        return -1;
    }
    memorystatus_priority_entry_t *list = (memorystatus_priority_entry_t *)malloc(size);
    if (!list) {
        JetLog(@"<Jetsam> malloc failed for size %d", size);
        return -1;
    }
    int ret = memorystatus_control(MEMORYSTATUS_CMD_GET_PRIORITY_LIST, 0, 0, list, size);
    if (ret < 0) {
        JetLog(@"<Jetsam> memorystatus_control list fetch failed: %d errno=%d", ret, errno);
        free(list);
        return -1;
    }
    int count = ret / (int)sizeof(memorystatus_priority_entry_t);
    int foundLimit = -1;
    for (int i = 0; i < count; ++i) {
        memorystatus_priority_entry_t *entry = list + i;
        if (entry->pid == pid) {
            foundLimit = entry->limit;
            break;
        }
    }
    free(list);
    return foundLimit;
}

- (int)setHighWaterMarkForPid:(int)pid limit:(int)limit {
    int cmd = MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK;
    int result = memorystatus_control(cmd, pid, limit, 0, 0);
    if (result != 0) {
        // memorystatus_control returns 0 on success, -1 on failure with errno set
        JetLog(@"<Jetsam> memorystatus_control set failed for pid %d limit %d errno=%d", pid, limit, errno);
    }
    return result;
}

- (BOOL)setPriority:(int)priority forPID:(int)pid {
    memorystatus_priority_properties_t props = {0};
    props.priority = priority;
    props.user_data = 0;

    int result = memorystatus_control(MEMORYSTATUS_CMD_SET_PRIORITY_PROPERTIES,
                                      pid, 0, &props, sizeof(props));
    if (result != 0) {
        JetLog(@"<Jetsam> Failed to set priority for pid %d: errno=%d", pid, errno);
        return NO;
    }

    NSLog(@"<Jetsam> Set priority=%d for pid=%d success", priority, pid);
    return YES;
}

#pragma mark - IPC reply helper

// Tùy CrossOverIPC, implement cách reply phù hợp. Đây là hàm generic:
// - sender có thể là object crossOver (hoặc dictionary chứa reply port), tùy API.
// Nếu API khác, hãy chỉnh lại theo project bạn.
- (void)replyWithName:(NSString *)name toSender:(id)sender userInfo:(NSDictionary *)info {
    if (!_cross) {
        JetLog(@"<Jetsam> no cross center to reply");
        return;
    }
    // Một số CrossOverIPC có method sendMessage:withUserInfo: hoặc postMessage:...
    // Thử gọi phổ biến:
    if ([_cross respondsToSelector:@selector(sendMessage:withUserInfo:)]) {
        // sendMessage:name withUserInfo:info
        [_cross performSelector:@selector(sendMessage:withUserInfo:) withObject:name withObject:info];
        return;
    }
    if ([_cross respondsToSelector:@selector(postMessage:withUserInfo:)]) {
        [_cross performSelector:@selector(postMessage:withUserInfo:) withObject:name withObject:info];
        return;
    }
    // fallback: nếu sender supports a reply method:
    if (sender && [sender respondsToSelector:@selector(replyWithName:withUserInfo:)]) {
        [sender performSelector:@selector(replyWithName:withUserInfo:) withObject:name withObject:info];
        return;
    }

    // Nếu không có API rõ ràng, log ra — bạn cần chỉnh theo CrossOverIPC thực tế.
    JetLog(@"<Jetsam> cannot reply: no send/post method on CrossOverIPC; name=%@", name);
}

#pragma mark - Message handlers

// expected selector signature: (id)sender withUserInfo:(NSDictionary *)info
- (void)handleGettingHighWaterMark:(id)sender withUserInfo:(NSDictionary *)info {
    // info có thể chứa @"pid" : @(1234)
    int pid = -1;
    if ([info isKindOfClass:[NSDictionary class]]) {
        id p = info[@"pid"];
        if ([p respondsToSelector:@selector(intValue)]) {
            pid = [p intValue];
        }
    }
    if (pid <= 0) {
        JetLog(@"<Jetsam> handleGettingHighWaterMark invalid pid: %@ (info=%@)", info[@"pid"], info);
        NSDictionary *resp = @{ @"ok": @NO, @"error": @"invalid pid" };
        [self replyWithName:@"gettingHighWaterMarkReply" toSender:sender userInfo:resp];
        return;
    }

    int limit = [self getHighWaterMarkForPid:pid];
    NSDictionary *resp = @{ @"ok": @YES, @"pid": @(pid), @"limit": @(limit) };
    [self replyWithName:@"gettingHighWaterMarkReply" toSender:sender userInfo:resp];
}

- (void)handleSetupHighWaterMark:(id)sender withUserInfo:(NSDictionary *)info {
    int pid = -1;
    int limit = -1;
    if ([info isKindOfClass:[NSDictionary class]]) {
        id p = info[@"pid"];
        id l = info[@"limit"];
        if ([p respondsToSelector:@selector(intValue)]) pid = [p intValue];
        if ([l respondsToSelector:@selector(intValue)]) limit = [l intValue];
    }
    if (pid <= 0 || limit <= 0) {
        JetLog(@"<Jetsam> handleSetupHighWaterMark invalid args pid=%d limit=%d info=%@", pid, limit, info);
        NSDictionary *resp = @{ @"ok": @NO, @"error": @"invalid args" };
        [self replyWithName:@"setupHighWaterMarkReply" toSender:sender userInfo:resp];
        return;
    }

    int res = [self setHighWaterMarkForPid:pid limit:limit];
    BOOL ok = (res == 0);
    NSDictionary *resp = @{ @"ok": @(ok), @"pid": @(pid), @"limit": @(limit), @"result": @(res) };
    [self replyWithName:@"setupHighWaterMarkReply" toSender:sender userInfo:resp];
}

- (void)handleSetupPriority:(NSString *)message withUserInfo:(NSDictionary *)info {
    int pid = [info[@"pid"] intValue];
    int priority = [info[@"priority"] intValue];
    
    if (pid > 0 && priority >= 0) {
        [self setPriority:priority forPID:pid];
        // BOOL ok = [self setPriority:priority forPID:pid];
        // NSString *result = ok ? @"OK" : @"FAILED";
    }
}

@end

int main(int argc, char **argv, char **envp) {
	setuid(0);
	setgid(0);

    JetLog(@"[JetsamMain] Started. Runloop begin.");
    [[JetsamManager sharedManager] startListening];

	CFRunLoopRun();
    return 0;
}
