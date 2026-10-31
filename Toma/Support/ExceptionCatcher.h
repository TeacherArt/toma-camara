#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Atrapa excepciones de Objective-C (por ejemplo, ajustes de cámara que el iPhone rechaza)
/// para que la app muestre el error en vez de cerrarse.
@interface ExceptionCatcher : NSObject

/// Ejecuta el bloque. Devuelve nil si todo salió bien, o la descripción de la excepción.
+ (nullable NSString *)catchException:(void (NS_NOESCAPE ^)(void))block;

@end

NS_ASSUME_NONNULL_END
