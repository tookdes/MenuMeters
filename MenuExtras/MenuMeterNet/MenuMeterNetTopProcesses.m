//
//  MenuMeterNetTopProcesses.m
//
//  Reader object for top network using process list
//  Mirrors MenuMeterCPUTopProcesses pattern:
//  long-running shell task + async NSFileHandle reads
//

#import "MenuMeterNetTopProcesses.h"
#import "MenuMeterNet.h"

NSString* const kNetProcessPIDKey            = @"pid";
NSString* const kNetProcessNameKey           = @"processName";
NSString* const kNetProcessBytesInPerSecKey  = @"bytesInPerSec";
NSString* const kNetProcessBytesOutPerSecKey = @"bytesOutPerSec";

@interface MenuMeterNetTopProcesses (Private)
- (void)consumeTaskOutput:(NSData *)chunk fileHandle:(NSFileHandle *)fh;
@end

@implementation MenuMeterNetTopProcesses
{
    NSArray *processes;
    NSTask *task;
    NSPipe *pipe;
    NSMutableData *buffer;
    int parseState; // 0 = before PROCESS_LIST; 1 = inside PROCESS_LIST
    NSMutableArray *tempArray;
}

- (instancetype)init {
    self = [super init];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(taskOutput:)
                                                 name:NSFileHandleReadCompletionNotification
                                               object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopUpdateProcessList];
}

- (void)taskOutput:(NSNotification *)n {
    NSFileHandle *fh = [n object];
    if (![[pipe fileHandleForReading] isEqualTo:fh]) {
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

- (void)startUpdateProcessList {
    [self stopUpdateProcessList];

    parseState = 0;
    buffer = [NSMutableData data];

    task = [NSTask new];
    task.launchPath = @"/bin/sh";
    // Shell script that runs nettop repeatedly, computes per-second deltas
    // via awk, and outputs PROCESS_LIST/END_PROCESS_LIST markers.
    // Temp files live in a private mktemp directory under TMPDIR.
    NSString *script = [@[
        @"tmpdir=$(mktemp -d \"${TMPDIR:-/tmp}/mm_nettop.XXXXXX\") || exit 1;",
        @"prev=\"$tmpdir/prev\";",
        @"curr=\"$tmpdir/curr\";",
        @"trap 'rm -rf \"$tmpdir\"' EXIT;",
        @": > \"$prev\";",
        @"pt=$(date +%s);",
        @"while true; do ",
        @"/usr/bin/nettop -L 1 -P -x -J bytes_in,bytes_out 2>/dev/null > \"$curr\";",
        @"ct=$(date +%s);",
        @"el=$((ct - pt));",
        @"[ \"$el\" -lt 1 ] && el=1;",
        @"awk -F, -v el=\"$el\" '",
        @"FILENAME==ARGV[1]{",
            @"if(FNR==1){for(i=1;i<=NF;i++){if($i==\"bytes_in\")pi=i;if($i==\"bytes_out\")po=i}next}",
            @"if(pi<1||po<1)next;",
            @"f=$1;n=split(f,p,\".\");pid=p[n];nm=p[1];for(i=2;i<n;i++)nm=nm\".\"p[i];",
            @"if(pid+0<=0)next;",
            @"pI[pid]=$pi+0;pO[pid]=$po+0;pN[pid]=nm;",
            @"next}",
        @"FILENAME==ARGV[2]{",
            @"if(FNR==1){for(i=1;i<=NF;i++){if($i==\"bytes_in\")ci=i;if($i==\"bytes_out\")co=i}next}",
            @"if(ci<1||co<1)next;",
            @"f=$1;n=split(f,p,\".\");pid=p[n];nm=p[1];for(i=2;i<n;i++)nm=nm\".\"p[i];",
            @"if(pid+0<=0)next;",
            @"cI[pid]=$ci+0;cO[pid]=$co+0;cN[pid]=nm}",
        @"END{",
            @"n=0;",
            @"for(pid in cI){",
                @"if(pid in pI){",
                    @"bi=(cI[pid]-pI[pid])/el;if(bi<0)bi=0;",
                    @"bo=(cO[pid]-pO[pid])/el;if(bo<0)bo=0;",
                    @"t=bi+bo;",
                    @"if(t>=1024){rn[n]=cN[pid];rp[n]=pid;ri[n]=bi;ro[n]=bo;rt[n]=t;n++}",
                @"}",
            @"}",
            @"for(i=0;i<n-1;i++)for(j=i+1;j<n;j++)if(rt[j]>rt[i]){",
                @"t=rt[i];rt[i]=rt[j];rt[j]=t;",
                @"t=ri[i];ri[i]=ri[j];ri[j]=t;",
                @"t=ro[i];ro[i]=ro[j];ro[j]=t;",
                @"t=rp[i];rp[i]=rp[j];rp[j]=t;",
                @"t=rn[i];rn[i]=rn[j];rn[j]=t}",
            @"print \"PROCESS_LIST\";",
            [NSString stringWithFormat:@"for(i=0;i<n&&i<%d;i++)print rp[i],int(ri[i]),int(ro[i]),rn[i];", kNetProcessCountMax],
            @"print \"END_PROCESS_LIST\";",
            @"fflush()}",
        @"' \"$prev\" \"$curr\";",
        @"cp \"$curr\" \"$prev\";",
        @"pt=$ct;",
        @"sleep 1;",
        @"done"
    ] componentsJoinedByString:@""];
    task.arguments = @[@"-c", script];

    pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    [[pipe fileHandleForReading] readInBackgroundAndNotifyForModes:@[NSRunLoopCommonModes]];
    @try {
        [task launch];
    } @catch (NSException *e) {
        NSLog(@"MenuMeterNetTopProcesses: launch failed: %@", e);
        task = nil;
        pipe = nil;
        buffer = nil;
    }
}

- (void)stopUpdateProcessList {
    if (task.running) {
        [task terminate];
    }
    task = nil;
    pipe = nil;
    buffer = nil;
}

- (NSArray *)runningProcessesByNetUsage:(NSUInteger)maxItem {
    if (!processes) return @[];
    return [processes subarrayWithRange:NSMakeRange(0, MIN(maxItem, processes.count))];
}

- (void)dealWithLine:(NSString *)s {
    if (parseState == 0) {
        if ([s hasPrefix:@"PROCESS_LIST"]) {
            parseState = 1;
            tempArray = [NSMutableArray array];
        }
        return;
    }
    if ([s hasPrefix:@"END_PROCESS_LIST"]) {
        parseState = 0;
        processes = tempArray;
        return;
    }

    // Parse: PID BYTES_IN_PER_SEC BYTES_OUT_PER_SEC NAME...
    NSArray *a = [s componentsSeparatedByString:@" "];
    NSMutableArray *x = [NSMutableArray array];
    for (NSString *i in a) {
        if (![i isEqualToString:@""]) {
            [x addObject:i];
        }
    }
    if (x.count < 4) return;

    NSArray *nameParts = [x subarrayWithRange:NSMakeRange(3, x.count - 3)];
    NSDictionary *entry = @{
        kNetProcessPIDKey: x[0],
        kNetProcessBytesInPerSecKey: x[1],
        kNetProcessBytesOutPerSecKey: x[2],
        kNetProcessNameKey: [nameParts componentsJoinedByString:@" "]
    };
    [tempArray addObject:entry];
}

@end
