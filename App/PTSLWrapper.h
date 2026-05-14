#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const PTSLRuntimeLogNotification;
FOUNDATION_EXPORT NSString *const PTSLRuntimeLogMessageKey;

@interface PTSLManager : NSObject

+ (instancetype)shared;

- (NSDictionary *)hostReadyStatus;
- (NSDictionary *)exportMusicEDLForTrackNames:(NSArray<NSString *> *)trackNames;
- (NSDictionary *)exportMusicEDLForSelectedTracks;
- (NSDictionary *)availableMarkerRulerNames;
- (NSDictionary *)importMusicMarkers:(NSArray<NSDictionary *> *)markers;

@end

NS_ASSUME_NONNULL_END
