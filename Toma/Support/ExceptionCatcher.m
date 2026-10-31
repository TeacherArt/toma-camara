#import "ExceptionCatcher.h"

@implementation ExceptionCatcher

+ (nullable NSString *)catchException:(void (NS_NOESCAPE ^)(void))block {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        NSLog(@"[Toma] Excepción atrapada: %@ — %@", exception.name, exception.reason);
        return [NSString stringWithFormat:@"%@ (%@)", exception.reason ?: @"sin detalle", exception.name];
    }
}

@end
