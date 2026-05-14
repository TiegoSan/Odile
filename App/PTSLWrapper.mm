#import "PTSLWrapper.h"

#include <PTSLC_CPP/CppPTSLClient.h>
#include <PTSLC_CPP/CppPTSLCommon.h>

using namespace PTSLC_CPP;

static NSString *const PTSLErrorDomain = @"Odile.PTSL";
NSString *const PTSLRuntimeLogNotification = @"PTSLRuntimeLogNotification";
NSString *const PTSLRuntimeLogMessageKey = @"message";

@interface PTSLManager ()
@end

@implementation PTSLManager {
    std::shared_ptr<CppPTSLClient> _client;
    BOOL _isRegistered;
}

+ (instancetype)shared {
    static PTSLManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PTSLManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        ClientConfig config;
        config.serverMode = Mode::Mode_ProTools;
        config.skipHostLaunch = SkipHostLaunch::SHLaunch_Yes;
        config.address = "localhost:31416";
        _client = std::make_shared<CppPTSLClient>(config);
        _isRegistered = NO;
    }
    return self;
}

- (NSDictionary *)hostReadyStatus {
    NSError *error = nil;
    if (![self ensureRegistered:&error]) {
        return @{
            @"ok": @NO,
            @"is_ready": @NO,
            @"error": error.localizedDescription ?: @"RegisterConnection failed"
        };
    }

    CppPTSLRequest request(CommandId::CId_HostReadyCheck, "");
    CppPTSLResponse response = _client->SendRequest(request).get();
    if (response.GetStatus() != TaskStatus::TStatus_Completed) {
        NSString *err = [NSString stringWithUTF8String:response.GetResponseErrorJson().c_str()];
        return @{
            @"ok": @NO,
            @"is_ready": @NO,
            @"error": err.length > 0 ? err : @"HostReadyCheck failed"
        };
    }

    NSString *json = [NSString stringWithUTF8String:response.GetResponseBodyJson().c_str()];
    NSDictionary *payload = [self parseJson:json] ?: @{};
    BOOL isReady = [payload[@"is_host_ready"] respondsToSelector:@selector(boolValue)] ? [payload[@"is_host_ready"] boolValue] : YES;
    return @{ @"ok": @YES, @"is_ready": @(isReady) };
}

- (NSDictionary *)exportMusicEDLForTrackNames:(NSArray<NSString *> *)trackNames {
    NSArray<NSString *> *targets = [self normalizedTrackNames:trackNames];
    if (targets.count == 0) {
        return [self failurePayload:@"No music track requested"];
    }

    NSError *error = nil;
    NSDictionary *trackPayload = nil;
    NSString *trackBody = [self jsonStringFromObject:@{
        @"track_filter_list": @[],
        @"is_filter_list_additive": @YES,
        @"pagination_request": @{ @"limit": @0, @"offset": @0 }
    }];

    if (![self sendCommand:CommandId::CId_GetTrackList
                      body:trackBody
           responsePayload:&trackPayload
                     error:&error]) {
        return [self failurePayload:error.localizedDescription ?: @"GetTrackList failed"];
    }

    NSArray *trackList = [trackPayload[@"track_list"] isKindOfClass:[NSArray class]] ? trackPayload[@"track_list"] : @[];
    NSDictionary<NSString *, NSString *> *availableByKey = [self availableTrackNamesByKey:trackList];
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    NSMutableArray<NSString *> *missing = [NSMutableArray array];

    for (NSString *target in targets) {
        NSString *actual = availableByKey[[self canonicalTrackKey:target]];
        if (actual.length > 0) {
            [found addObject:actual];
        } else {
            [missing addObject:target];
        }
    }

    NSDictionary *exportBody = @{
        @"include_file_list": @NO,
        @"include_clip_list": @NO,
        @"include_markers": @NO,
        @"include_plugin_list": @NO,
        @"include_track_edls": @YES,
        @"show_sub_frames": @YES,
        @"include_user_timestamps": @NO,
        @"track_list_type": @"AllTracks",
        @"fade_handling_type": @"ShowCrossfades",
        @"track_offset_options": @"TimeCode",
        @"text_as_file_format": @"UTF8",
        @"output_type": @"ESI_String",
        @"output_path": @""
    };

    NSDictionary *sessionInfoPayload = nil;
    if (![self sendCommand:CommandId::CId_ExportSessionInfoAsText
                      body:[self jsonStringFromObject:exportBody]
           responsePayload:&sessionInfoPayload
                     error:&error]) {
        return [self failurePayload:error.localizedDescription ?: @"ExportSessionInfoAsText failed"];
    }

    NSString *sessionInfo = [sessionInfoPayload[@"session_info"] isKindOfClass:[NSString class]] ? sessionInfoPayload[@"session_info"] : @"";
    if (sessionInfo.length == 0) {
        return [self failurePayload:@"ExportSessionInfoAsText a retourne une EDL vide"];
    }

    NSDictionary *sessionNamePayload = nil;
    NSString *sessionName = @"";
    if ([self sendCommand:CommandId::CId_GetSessionName body:@"" responsePayload:&sessionNamePayload error:nil]) {
        sessionName = [sessionNamePayload[@"session_name"] isKindOfClass:[NSString class]] ? sessionNamePayload[@"session_name"] : @"";
    }

    return @{
        @"ok": @YES,
        @"session_name": sessionName ?: @"",
        @"session_info": sessionInfo,
        @"requested_tracks": targets,
        @"found_tracks": found,
        @"missing_tracks": missing
    };
}

- (NSDictionary *)exportMusicEDLForSelectedTracks {
    NSError *error = nil;
    NSDictionary *trackPayload = nil;
    NSString *trackBody = [self jsonStringFromObject:@{
        @"track_filter_list": @[
            @{
                @"filter": @"Selected",
                @"is_inverted": @NO
            }
        ],
        @"is_filter_list_additive": @YES,
        @"pagination_request": @{ @"limit": @0, @"offset": @0 }
    }];

    if (![self sendCommand:CommandId::CId_GetTrackList
                      body:trackBody
           responsePayload:&trackPayload
                     error:&error]) {
        return [self failurePayload:error.localizedDescription ?: @"GetTrackList selected failed"];
    }

    NSArray *trackList = [trackPayload[@"track_list"] isKindOfClass:[NSArray class]] ? trackPayload[@"track_list"] : @[];
    NSMutableArray<NSString *> *selected = [NSMutableArray array];
    for (id item in trackList) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = ((NSDictionary *)item)[@"name"];
        if ([name isKindOfClass:[NSString class]] && name.length > 0) {
            [selected addObject:name];
        }
    }

    if (selected.count == 0) {
        return [self failurePayload:@"No track selected in Pro Tools"];
    }

    NSDictionary *exportBody = @{
        @"include_file_list": @NO,
        @"include_clip_list": @NO,
        @"include_markers": @NO,
        @"include_plugin_list": @NO,
        @"include_track_edls": @YES,
        @"show_sub_frames": @YES,
        @"include_user_timestamps": @NO,
        @"track_list_type": @"AllTracks",
        @"fade_handling_type": @"ShowCrossfades",
        @"track_offset_options": @"TimeCode",
        @"text_as_file_format": @"UTF8",
        @"output_type": @"ESI_String",
        @"output_path": @""
    };

    NSDictionary *sessionInfoPayload = nil;
    if (![self sendCommand:CommandId::CId_ExportSessionInfoAsText
                      body:[self jsonStringFromObject:exportBody]
           responsePayload:&sessionInfoPayload
                     error:&error]) {
        return [self failurePayload:error.localizedDescription ?: @"ExportSessionInfoAsText failed"];
    }

    NSString *sessionInfo = [sessionInfoPayload[@"session_info"] isKindOfClass:[NSString class]] ? sessionInfoPayload[@"session_info"] : @"";
    if (sessionInfo.length == 0) {
        return [self failurePayload:@"ExportSessionInfoAsText a retourne une EDL vide"];
    }

    NSDictionary *sessionNamePayload = nil;
    NSString *sessionName = @"";
    if ([self sendCommand:CommandId::CId_GetSessionName body:@"" responsePayload:&sessionNamePayload error:nil]) {
        sessionName = [sessionNamePayload[@"session_name"] isKindOfClass:[NSString class]] ? sessionNamePayload[@"session_name"] : @"";
    }

    return @{
        @"ok": @YES,
        @"session_name": sessionName ?: @"",
        @"session_info": sessionInfo,
        @"requested_tracks": selected,
        @"found_tracks": selected,
        @"missing_tracks": @[]
    };
}

- (NSDictionary *)availableMarkerRulerNames {
    NSError *error = nil;
    NSDictionary *memoryPayload = nil;
    NSString *getBody = [self jsonStringFromObject:@{
        @"pagination_request": @{ @"limit": @0, @"offset": @0 }
    }];

    if (![self sendCommand:CommandId::CId_GetMemoryLocations
                      body:getBody
           responsePayload:&memoryPayload
                     error:&error]) {
        return [self failurePayload:error.localizedDescription ?: @"GetMemoryLocations failed"];
    }

    NSMutableOrderedSet<NSString *> *rulerNames = [NSMutableOrderedSet orderedSet];
    [rulerNames addObject:@"Markers"];

    NSArray *existing = [memoryPayload[@"memory_locations"] isKindOfClass:[NSArray class]] ? memoryPayload[@"memory_locations"] : @[];
    for (id item in existing) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *trackName = ((NSDictionary *)item)[@"track_name"];
        if (![trackName isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *trimmed = [trackName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [rulerNames addObject:trimmed];
        }
    }

    return @{
        @"ok": @YES,
        @"ruler_names": rulerNames.array ?: @[]
    };
}

- (NSDictionary *)importMusicMarkers:(NSArray<NSDictionary *> *)markers {
    if (markers.count == 0) {
        return [self failurePayload:@"Aucun marker a importer"];
    }

    NSError *error = nil;
    NSDictionary *memoryPayload = nil;
    NSString *getBody = [self jsonStringFromObject:@{
        @"pagination_request": @{ @"limit": @0, @"offset": @0 }
    }];

    if (![self sendCommand:CommandId::CId_GetMemoryLocations
                      body:getBody
           responsePayload:&memoryPayload
                     error:&error]) {
        return [self failurePayload:error.localizedDescription ?: @"GetMemoryLocations failed"];
    }

    NSMutableSet<NSNumber *> *usedNumbers = [NSMutableSet set];
    NSArray *existing = [memoryPayload[@"memory_locations"] isKindOfClass:[NSArray class]] ? memoryPayload[@"memory_locations"] : @[];
    for (id item in existing) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        id number = ((NSDictionary *)item)[@"number"];
        if ([number respondsToSelector:@selector(integerValue)] && [number integerValue] > 0) {
            [usedNumbers addObject:@([number integerValue])];
        }
    }

    NSInteger successCount = 0;
    NSMutableArray<NSString *> *failureList = [NSMutableArray array];

    for (NSDictionary *marker in markers) {
        NSString *name = [self safeMarkerName:[marker[@"name"] isKindOfClass:[NSString class]] ? marker[@"name"] : @""];
        NSString *startTime = [marker[@"start_time"] isKindOfClass:[NSString class]] ? marker[@"start_time"] : @"";
        NSString *endTime = [marker[@"end_time"] isKindOfClass:[NSString class]] ? marker[@"end_time"] : @"";
        NSString *comments = [marker[@"comments"] isKindOfClass:[NSString class]] ? marker[@"comments"] : @"";
        NSInteger colorIndex = [marker[@"color_index"] isKindOfClass:[NSNumber class]] ? [marker[@"color_index"] integerValue] : 0;
        NSString *rulerName = [marker[@"ruler_name"] isKindOfClass:[NSString class]] ? marker[@"ruler_name"] : @"";
        NSString *trimmedRuler = [rulerName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        BOOL hasRuler = trimmedRuler.length > 0;

        if (name.length == 0 || startTime.length == 0) {
            [failureList addObject:name.length > 0 ? name : @"Marker sans nom/timecode"];
            continue;
        }

        NSInteger number = [self nextAvailableMemoryLocationNumberFrom:usedNumbers];
        [usedNumbers addObject:@(number)];

        BOOL hasSelectionEnd = endTime.length > 0 && ![endTime isEqualToString:startTime];
        NSDictionary *createBody = @{
            @"number": @(number),
            @"name": name,
            @"start_time": startTime,
            @"end_time": hasSelectionEnd ? endTime : startTime,
            @"time_properties": hasSelectionEnd ? @"TP_Selection" : @"TP_Marker",
            @"reference": @"MLR_FollowTrackTimebase",
            @"general_properties": @{
                @"zoom_settings": @NO,
                @"pre_post_roll_times": @NO,
                @"track_visibility": @NO,
                @"track_heights": @NO,
                @"group_enables": @NO,
                @"window_configuration": @NO,
                @"window_configuration_index": @0,
                @"window_configuration_name": @"",
                @"venue_snapshot_index": @0,
                @"venue_snapshot_name": @""
            },
            @"comments": comments,
            @"color_index": @(colorIndex),
            @"location": hasRuler ? @"MarkerLocation_NamedRuler" : @"MLC_MainRuler",
            @"track_name": hasRuler ? trimmedRuler : @""
        };

        NSError *createError = nil;
        if ([self sendCommand:CommandId::CId_CreateMemoryLocation
                         body:[self jsonStringFromObject:createBody]
              responsePayload:nil
                        error:&createError]) {
            successCount += 1;
        } else {
            NSString *message = createError.localizedDescription ?: @"CreateMemoryLocation failed";
            [failureList addObject:[NSString stringWithFormat:@"%@: %@", name, message]];
        }
    }

    return @{
        @"ok": @(successCount > 0 && failureList.count == 0),
        @"success_count": @(successCount),
        @"failure_count": @(failureList.count),
        @"failure_list": failureList
    };
}

#pragma mark - PTSL

- (BOOL)sendCommand:(CommandId)command
               body:(NSString *)body
    responsePayload:(NSDictionary * _Nullable * _Nullable)responsePayload
              error:(NSError **)error {
    if (![self ensureRegistered:error]) {
        return NO;
    }

    std::string bodyUtf8 = body.length > 0 ? body.UTF8String : "";
    CppPTSLRequest request(command, bodyUtf8);
    CppPTSLResponse response = _client->SendRequest(request).get();
    if (response.GetStatus() == TaskStatus::TStatus_Completed) {
        if (responsePayload) {
            NSString *json = [NSString stringWithUTF8String:response.GetResponseBodyJson().c_str()];
            *responsePayload = [self parseJson:json] ?: @{};
        }
        return YES;
    }

    NSString *errorJson = [NSString stringWithUTF8String:response.GetResponseErrorJson().c_str()];
    if ([self isRegisterConnectionRequiredError:errorJson]) {
        _isRegistered = NO;
        _client->SetSessionId(std::string());
        if ([self ensureRegistered:error]) {
            CppPTSLRequest retryRequest(command, bodyUtf8);
            CppPTSLResponse retryResponse = _client->SendRequest(retryRequest).get();
            if (retryResponse.GetStatus() == TaskStatus::TStatus_Completed) {
                if (responsePayload) {
                    NSString *json = [NSString stringWithUTF8String:retryResponse.GetResponseBodyJson().c_str()];
                    *responsePayload = [self parseJson:json] ?: @{};
                }
                return YES;
            }
            errorJson = [NSString stringWithUTF8String:retryResponse.GetResponseErrorJson().c_str()];
        }
    }

    [self fillError:error
              code:(NSInteger)response.GetStatus()
           message:[self commandErrorMessage:errorJson fallback:@"PTSL command failed"]];
    return NO;
}

- (BOOL)ensureRegistered:(NSError **)error {
    if (_isRegistered) {
        return YES;
    }

    if (!_client) {
        [self fillError:error code:900 message:@"PTSL client not initialized"];
        return NO;
    }

    CppPTSLRequest readyRequest(CommandId::CId_HostReadyCheck, "");
    CppPTSLResponse readyResponse = _client->SendRequest(readyRequest).get();
    if (readyResponse.GetStatus() != TaskStatus::TStatus_Completed) {
        NSString *err = [NSString stringWithUTF8String:readyResponse.GetResponseErrorJson().c_str()];
        [self fillError:error code:901 message:[self commandErrorMessage:err fallback:@"Pro Tools n'est pas disponible"]];
        return NO;
    }

    NSString *registerJson = [self jsonStringFromObject:@{
        @"company_name": @"GogoLabs",
        @"application_name": @"Odile"
    }];

    CppPTSLRequest registerRequest(CommandId::CId_RegisterConnection, registerJson.UTF8String);
    CppPTSLResponse registerResponse = _client->SendRequest(registerRequest).get();
    if (registerResponse.GetStatus() != TaskStatus::TStatus_Completed) {
        NSString *err = [NSString stringWithUTF8String:registerResponse.GetResponseErrorJson().c_str()];
        [self fillError:error code:902 message:[self commandErrorMessage:err fallback:@"RegisterConnection failed"]];
        return NO;
    }

    NSString *responseBody = [NSString stringWithUTF8String:registerResponse.GetResponseBodyJson().c_str()];
    NSDictionary *payload = [self parseJson:responseBody];
    NSString *sessionID = [payload[@"session_id"] isKindOfClass:[NSString class]] ? payload[@"session_id"] : @"";
    if (sessionID.length == 0) {
        [self fillError:error code:903 message:@"RegisterConnection returned empty session_id"];
        return NO;
    }

    _client->SetSessionId(sessionID.UTF8String);
    _isRegistered = YES;
    return YES;
}

#pragma mark - Helpers

- (NSArray<NSString *> *)normalizedTrackNames:(NSArray<NSString *> *)trackNames {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id item in trackNames ?: @[]) {
        if (![item isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *name = [(NSString *)item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length > 0) {
            [names addObject:name];
        }
    }
    return [[NSOrderedSet orderedSetWithArray:names] array];
}

- (NSDictionary<NSString *, NSString *> *)availableTrackNamesByKey:(NSArray *)trackList {
    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
    for (id item in trackList ?: @[]) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = [((NSDictionary *)item)[@"name"] isKindOfClass:[NSString class]] ? ((NSDictionary *)item)[@"name"] : @"";
        NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            result[[self canonicalTrackKey:trimmed]] = trimmed;
        }
    }
    return result;
}

- (NSString *)canonicalTrackKey:(NSString *)trackName {
    if (trackName.length == 0) {
        return @"";
    }

    NSString *withoutFormat = [trackName stringByReplacingOccurrencesOfString:@"\\s+\\([^)]*\\)\\s*$"
                                                                    withString:@""
                                                                       options:NSRegularExpressionSearch
                                                                         range:NSMakeRange(0, trackName.length)];
    NSString *lower = withoutFormat.lowercaseString;
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *out = [NSMutableString stringWithCapacity:lower.length];
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar ch = [lower characterAtIndex:i];
        if ([allowed characterIsMember:ch]) {
            [out appendFormat:@"%C", ch];
        }
    }
    return out;
}

- (BOOL)isRegisterConnectionRequiredError:(NSString *)errorJson {
    return [errorJson containsString:@"RegisterConnection command first"] ||
           [errorJson containsString:@"session_id"] ||
           [errorJson containsString:@"No valid session"];
}

- (NSString *)commandErrorMessage:(NSString *)errorJson fallback:(NSString *)fallback {
    NSDictionary *payload = [self parseJson:errorJson];
    NSString *details = [payload[@"details"] isKindOfClass:[NSString class]] ? payload[@"details"] : @"";
    NSString *message = [payload[@"message"] isKindOfClass:[NSString class]] ? payload[@"message"] : @"";
    if (details.length > 0) {
        return details;
    }
    if (message.length > 0) {
        return message;
    }
    if (errorJson.length > 0) {
        return errorJson;
    }
    return fallback ?: @"Unknown PTSL error";
}

- (NSDictionary *)parseJson:(NSString *)json {
    if (json.length == 0) {
        return nil;
    }

    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return nil;
    }

    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![obj isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return (NSDictionary *)obj;
}

- (NSString *)jsonStringFromObject:(id)obj {
    if (!obj) {
        return @"{}";
    }

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&error];
    if (!data || error) {
        return @"{}";
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}

- (NSDictionary *)failurePayload:(NSString *)message {
    return @{ @"ok": @NO, @"error": message ?: @"Unknown error" };
}

- (NSInteger)nextAvailableMemoryLocationNumberFrom:(NSMutableSet<NSNumber *> *)usedNumbers {
    NSInteger number = 1;
    while ([usedNumbers containsObject:@(number)]) {
        number += 1;
    }
    return number;
}

- (NSString *)safeMarkerName:(NSString *)name {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return @"Music EDL";
    }
    if (trimmed.length <= 120) {
        return trimmed;
    }
    return [[trimmed substringToIndex:120] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)fillError:(NSError **)error code:(NSInteger)code message:(NSString *)message {
    if (!error) {
        return;
    }

    *error = [NSError errorWithDomain:PTSLErrorDomain
                                 code:code
                             userInfo:@{ NSLocalizedDescriptionKey: message ?: @"Unknown error" }];
}

@end
