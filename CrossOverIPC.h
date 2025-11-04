#include <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>

// https://github.com/crazymind90/CrossOverIPC

#include <pthread.h>
#include <time.h>
#include <dlfcn.h>
#include <objc/runtime.h>  
 
typedef enum CrossOverIPCServiceType : CFIndex {

    SERVICE_TYPE_SENDER,
    SERVICE_TYPE_LISTENER

} CrossOverIPCServiceType;


@interface CrossOverIPC : NSObject 

+ (instancetype) centerNamed:(NSString *)serviceName type:(CrossOverIPCServiceType)type;
- (void) sendMessageName:(NSString *)msgName userInfo:(NSDictionary *)userInfo;
- (NSDictionary *) sendMessageAndReceiveReplyName:(NSString *)msgName userInfo:(NSDictionary *)userInfo;
- (void) registerForMessageName:(NSString *)msgName target:(id)target selector:(SEL)sel;


@end
