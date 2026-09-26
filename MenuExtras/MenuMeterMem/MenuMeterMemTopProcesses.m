//
//  MenuMeterMemTopProcesses.m
//
//  Reader object for top memory using process list
//  Uses direct proc_pidinfo for instant initial results, then
//  /usr/bin/top in continuous mode for ongoing accurate updates.
//

#import "MenuMeterMemTopProcesses.h"
#import "MenuMeterMem.h"
#import <libproc.h>
#import <sys/proc_info.h>

NSString* const kMemProcessPIDKey       = @"pid";
NSString* const kMemProcessNameKey      = @"processName";
NSString* const kMemProcessMemBytesKey  = @"memBytes";
NSString* const kMemTopProcessesUpdatedNotification = @"MenuMeterMemTopProcessesUpdated";

@interface MenuMeterMemTopProcesses (Private)
- (void)consumeTaskOutput:(NSData *)chunk fileHandle:(NSFileHandle *)fh;
@end

@implementation MenuMeterMemTopProcesses
{
    NSArray *processes;
    NSTask *task;
    NSPipe *outPipe;
    NSMutableData *buffer;
    int parseState; // 0 = before PID header, 1 = reading process lines
    NSMutableArray *tempArray;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(taskOutput:)
                                                     name:NSFileHandleReadCompletionNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopUpdateProcessList];
}

- (void)startUpdateProcessList {
    [self stopUpdateProcessList];

    // Immediate fetch using proc_pidinfo (instant, no subprocess)
    [self fetchProcessListDirect];

    // Start continuous top for ongoing updates (first output after ~2s)
    parseState = 0;
    buffer = [NSMutableData data];
    task = [NSTask new];
    task.launchPath = @"/usr/bin/top";
    task.arguments = @[@"-s", @"2", @"-l", @"0", @"-o", @"mem", @"-stats", @"pid,mem,command", @"-n", [NSString stringWithFormat:@"%d", kMemProcessCountMax]];
    outPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = [NSPipe pipe];
    [[outPipe fileHandleForReading] readInBackgroundAndNotifyForModes:@[NSRunLoopCommonModes]];
    @try {
        [task launch];
    } @catch (NSException *e) {
        task = nil;
        outPipe = nil;
        buffer = nil;
        return;
    }
}

- (void)fetchProcessListDirect {
    int bufferSize = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bufferSize <= 0) return;

    pid_t *pids = calloc(bufferSize, sizeof(pid_t));
    if (!pids) return;
    int bytesFilled = proc_listpids(PROC_ALL_PIDS, 0, pids, bufferSize * sizeof(pid_t));
    int count = bytesFilled / sizeof(pid_t);

    NSMutableArray *list = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        if (pids[i] == 0) continue;

        struct proc_taskinfo taskInfo;
        int size = proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &taskInfo, sizeof(taskInfo));
        if (size != (int)sizeof(taskInfo)) continue;

        uint64_t memBytes = taskInfo.pti_resident_size;
        if (memBytes < 1024 * 1024) continue; // Skip < 1MB

        NSString *name = nil;
        char procName[256] = {0};
        proc_name(pids[i], procName, sizeof(procName));
        if (procName[0] != '\0') {
            name = [NSString stringWithUTF8String:procName];
        } else {
            char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
            if (proc_pidpath(pids[i], path, sizeof(path)) > 0) {
                name = [[NSString stringWithUTF8String:path] lastPathComponent];
            }
        }
        if (!name || name.length == 0) continue;

        [list addObject:@{
            kMemProcessPIDKey: @(pids[i]),
            kMemProcessNameKey: name,
            kMemProcessMemBytesKey: @(memBytes)
        }];
    }
    free(pids);

    // Sort by memory descending
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[kMemProcessMemBytesKey] compare:a[kMemProcessMemBytesKey]];
    }];

    if (list.count > (NSUInteger)kMemProcessCountMax) {
        [list removeObjectsInRange:NSMakeRange(kMemProcessCountMax, list.count - kMemProcessCountMax)];
    }

    processes = list;
    [[NSNotificationCenter defaultCenter] postNotificationName:kMemTopProcessesUpdatedNotification object:self];
}

- (void)stopUpdateProcessList {
    if (task.running) {
        [task terminate];
    }
    task = nil;
    outPipe = nil;
    buffer = nil;
}

- (void)taskOutput:(NSNotification *)n {
    NSFileHandle *fh = [n object];
    if (![[outPipe fileHandleForReading] isEqualTo:fh]) {
        return;
    }
    NSData *d = [n userInfo][@"NSFileHandleNotificationDataItem"];
    if ([d length]) {
        [self consumeTaskOutput:d fileHandle:fh];
    }
}

- (void)consumeTaskOutput:(NSData *)chunk fileHandle:(NSFileHandle *)fh {
    if (!buffer) {
        buffer = [NSMutableData data];
    }
    [buffer appendData:chunk];

    const uint8_t *bytes = buffer.bytes;
    NSUInteger length = buffer.length;
    NSUInteger lineStart = 0;
    for (NSUInteger i = 0; i < length; i++) {
        if (bytes[i] != '\n') {
            continue;
        }
        NSUInteger lineLength = i - lineStart;
        if (lineLength > 0 && bytes[i - 1] == '\r') {
            lineLength -= 1;
        }
        NSData *lineData = [buffer subdataWithRange:NSMakeRange(lineStart, lineLength)];
        NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
        if (line) {
            [self dealWithLine:line];
        }
        lineStart = i + 1;
    }
    if (lineStart > 0) {
        [buffer replaceBytesInRange:NSMakeRange(0, lineStart) withBytes:NULL length:0];
    }
    [fh readInBackgroundAndNotifyForModes:@[NSRunLoopCommonModes]];
}

- (void)dealWithLine:(NSString *)s {
    if (parseState == 0) {
        if ([s hasPrefix:@"PID"]) {
            parseState = 1;
            tempArray = [NSMutableArray array];
        }
        return;
    }
    if ([s hasPrefix:@"Processes:"]) {
        parseState = 0;
        // One sample completed
        processes = tempArray;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMemTopProcessesUpdatedNotification object:self];
        return;
    }

    NSString *trimmed = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length == 0) return;

    // Process lines start with a digit (PID); skip anything else
    unichar firstChar = [trimmed characterAtIndex:0];
    if (firstChar < '0' || firstChar > '9') return;

    // Parse: PID  MEM  COMMAND
    NSArray *parts = [trimmed componentsSeparatedByString:@" "];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *p in parts) {
        if (p.length > 0) [tokens addObject:p];
    }
    if (tokens.count < 3) return;

    pid_t pid = [tokens[0] intValue];
    if (pid <= 0) return;

    // Parse memory value (e.g. "637M", "1024M+", "2G", "123K")
    NSString *memField = tokens[1];
    uint64_t memBytes = [self parseMemField:memField];
    if (memBytes < 1024 * 1024) return; // Skip < 1MB

    // Get full process name via proc_name (top truncates names)
    NSString *name = nil;
    char procName[256] = {0};
    proc_name(pid, procName, sizeof(procName));
    if (procName[0] != '\0') {
        name = [NSString stringWithUTF8String:procName];
    } else {
        // Fallback: try proc_pidpath for basename
        char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
        if (proc_pidpath(pid, path, sizeof(path)) > 0) {
            NSString *fullPath = [NSString stringWithUTF8String:path];
            name = [fullPath lastPathComponent];
        }
    }
    if (!name || name.length == 0) {
        // Last resort: use the truncated name from top
        NSArray *nameParts = [tokens subarrayWithRange:NSMakeRange(2, tokens.count - 2)];
        name = [nameParts componentsJoinedByString:@" "];
    }
    if (name.length == 0) return;

    [tempArray addObject:@{
        kMemProcessPIDKey: @(pid),
        kMemProcessNameKey: name,
        kMemProcessMemBytesKey: @(memBytes)
    }];
}

- (uint64_t)parseMemField:(NSString *)field {
    if (field.length == 0) return 0;

    // Strip trailing +/- (compression indicators)
    NSString *clean = field;
    unichar last = [clean characterAtIndex:clean.length - 1];
    if (last == '+' || last == '-') {
        clean = [clean substringToIndex:clean.length - 1];
    }
    if (clean.length == 0) return 0;

    last = [clean characterAtIndex:clean.length - 1];
    double multiplier = 1.0;
    if (last == 'K' || last == 'k') {
        multiplier = 1024.0;
        clean = [clean substringToIndex:clean.length - 1];
    } else if (last == 'M' || last == 'm') {
        multiplier = 1048576.0;
        clean = [clean substringToIndex:clean.length - 1];
    } else if (last == 'G' || last == 'g') {
        multiplier = 1073741824.0;
        clean = [clean substringToIndex:clean.length - 1];
    } else if (last == 'B' || last == 'b') {
        multiplier = 1.0;
        clean = [clean substringToIndex:clean.length - 1];
    }

    return (uint64_t)([clean doubleValue] * multiplier);
}

- (NSArray *)runningProcessesByMemUsage:(NSUInteger)maxItem {
    if (!processes) return @[];
    return [processes subarrayWithRange:NSMakeRange(0, MIN(maxItem, processes.count))];
}

@end
