//
//  MenuMeterNetStats.m
//
// 	Reader object for network throughput info
//
//	Copyright (c) 2002-2014 Alex Harper
//
// 	This file is part of MenuMeters.
//
// 	MenuMeters is free software; you can redistribute it and/or modify
// 	it under the terms of the GNU General Public License version 2 as
//  published by the Free Software Foundation.
//
// 	MenuMeters is distributed in the hope that it will be useful,
// 	but WITHOUT ANY WARRANTY; without even the implied warranty of
// 	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// 	GNU General Public License for more details.
//
// 	You should have received a copy of the GNU General Public License
// 	along with MenuMeters; if not, write to the Free Software
// 	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//

#import "MenuMeterNetStats.h"

static NSString * const kNetStatsSourceKey = @"source";
static NSString * const kNetStatsPPPSource = @"ppp";
static NSString * const kNetStatsPPPIdleSource = @"ppp-idle";
static NSString * const kNetStatsSysctlSource = @"sysctl";

@implementation MenuMeterNetStats

///////////////////////////////////////////////////////////////
//
//	init/dealloc
//
///////////////////////////////////////////////////////////////

- (id)init {

	self = [super init];
	if (!self) {
		return nil;
	}

	// Establish or connection to the PPP data gatherer
	pppGatherer = [MenuMeterNetPPP sharedPPP];
	if (!pppGatherer) {
		NSLog(@"MenuMeterNetStats unable to connect to PPP data gatherer. PPP stats disabled.");
	}

	// Prefetch the data first time
	[self netStatsForInterval:1.0f];

	return self;

} // init

- (void)dealloc {

	// Free our sysctl buffer
	if (sysctlBuffer) free(sysctlBuffer);

} // dealloc

///////////////////////////////////////////////////////////////
//
//	Net usage info, based mostly on code found in
//	XResourceGraph which got it in turn from gkrellm.
//	It reads data from the routing tables using sysctl,
//	which, unlike the kernel memory reads used in netstat
// 	and top, does not require root access
//
///////////////////////////////////////////////////////////////
- (void)resetTotalsForInterfaceName:(NSString*)interfaceName
{
    NSDictionary *oldStats = [lastData objectForKey:interfaceName];
    if(oldStats){
        NSMutableDictionary*x=[oldStats mutableCopy];
        x[@"totalin"]=@(0);
        x[@"totalout"]=@(0);
        lastData[interfaceName]=x;
    }
}
- (NSDictionary *)netStatsForInterval:(NSTimeInterval)sampleInterval {

	// Get sizing info from sysctl and resize as needed.
	int	mib[] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST, 0 };
	size_t currentSize = 0;
	if (sysctl(mib, 6, NULL, &currentSize, NULL, 0) != 0) return nil;
	if (!sysctlBuffer || (currentSize > sysctlBufferSize)) {
		if (sysctlBuffer) free(sysctlBuffer);
		sysctlBufferSize = 0;
		sysctlBuffer = malloc(currentSize);
		if (!sysctlBuffer) return nil;
		sysctlBufferSize = currentSize;
	}

	// Read in new data
	if (sysctl(mib, 6, sysctlBuffer, &currentSize, NULL, 0) != 0) return nil;

	// Walk through the reply
	uint8_t *currentData = sysctlBuffer;
	uint8_t *currentDataEnd = sysctlBuffer + currentSize;
	NSMutableDictionary	*newStats = [NSMutableDictionary dictionary];
	while (currentData + sizeof(struct if_msghdr) <= currentDataEnd) {
		// Expecting interface data
		struct if_msghdr *ifmsg = (struct if_msghdr *)currentData;
		if (ifmsg->ifm_msglen == 0 || currentData + ifmsg->ifm_msglen > currentDataEnd) {
			break;
		}
		if (ifmsg->ifm_type != RTM_IFINFO) {
			currentData += ifmsg->ifm_msglen;
			continue;
		}
		// Must not be loopback
		if (ifmsg->ifm_flags & IFF_LOOPBACK) {
			currentData += ifmsg->ifm_msglen;
			continue;
		}
		// Only look at link layer items
		struct sockaddr_dl *sdl = (struct sockaddr_dl *)(ifmsg + 1);
		if ((uint8_t *)(sdl + 1) > currentData + ifmsg->ifm_msglen) {
			currentData += ifmsg->ifm_msglen;
			continue;
		}
		if (sdl->sdl_family != AF_LINK) {
			currentData += ifmsg->ifm_msglen;
			continue;
		}
		// Build the interface name to string so we can key off it
		NSString *interfaceName = [[NSString alloc] initWithBytes:sdl->sdl_data length:sdl->sdl_nlen encoding:NSASCIIStringEncoding];
		if (!interfaceName) {
			currentData += ifmsg->ifm_msglen;
			continue;
		}
		// Load in old statistics for this interface
		NSDictionary *oldStats = [lastData objectForKey:interfaceName];

		BOOL handledAsPPP = NO;
		if ([interfaceName hasPrefix:@"ppp"] && pppGatherer) {
			// We handle PPP connections using data directly from ppp subsystem. On
			// old systems this was required because the outbytes from sysctl was
			// always zero.
			NSDictionary *pppStats = [pppGatherer statusForInterfaceName:interfaceName];
			handledAsPPP = (pppStats != nil);
			// Stats are only valid if PPP is running
			if ([[pppStats objectForKey:@"status"] intValue] == PPP_RUNNING) {
				if (oldStats && [[oldStats objectForKey:kNetStatsSourceKey] isEqualToString:kNetStatsPPPSource]) {
					// Calculate various stats in 64-bit with 32-bit overflow.
					// We know the PPP data is sized at 32-bits and we calc at 64-bits
					uint32_t ifIn = [[pppStats objectForKey:@"inBytes"] unsignedIntValue];
					uint32_t ifOut = [[pppStats objectForKey:@"outBytes"] unsignedIntValue];
					uint32_t lastifIn = [[oldStats objectForKey:@"ifin"] unsignedIntValue];
					uint32_t lastifOut = [[oldStats objectForKey:@"ifout"] unsignedIntValue];
					uint64_t lastTotalIn = [[oldStats objectForKey:@"totalin"] unsignedLongLongValue];
					uint64_t lastTotalOut = [[oldStats objectForKey:@"totalout"] unsignedLongLongValue];
					// New totals
					uint64_t totalIn = 0, totalOut = 0;
					if (lastifIn > ifIn) {
						totalIn = lastTotalIn + ifIn + UINT_MAX - lastifIn + 1;
					} else {
						totalIn = lastTotalIn + (ifIn - lastifIn);
					}
					if (lastifOut > ifOut) {
						totalOut = lastTotalOut + ifOut + UINT_MAX - lastifOut + 1;
					} else {
						totalOut = lastTotalOut + (ifOut - lastifOut);
					}
					// New deltas (64-bit overflow guard)
					uint64_t deltaIn = (totalIn > lastTotalIn) ? (totalIn - lastTotalIn) : 0;
					uint64_t deltaOut = (totalOut > lastTotalOut) ? (totalOut - lastTotalOut) : 0;
					// Peak
					double peak = [[oldStats objectForKey:@"peak"] doubleValue];
					if (sampleInterval > 0) {
						if (peak < (deltaIn / sampleInterval)) peak = deltaIn / sampleInterval;
						if (peak < (deltaOut / sampleInterval)) peak = deltaOut / sampleInterval;
					}
					[newStats setObject:[NSDictionary dictionaryWithObjectsAndKeys:
										[pppStats objectForKey:@"inBytes"],
										@"ifin",
										[pppStats objectForKey:@"outBytes"],
										@"ifout",
										[NSNumber numberWithUnsignedLongLong:deltaIn],
										@"deltain",
										[NSNumber numberWithUnsignedLongLong:deltaOut],
										@"deltaout",
										[NSNumber numberWithUnsignedLongLong:totalIn],
										@"totalin",
										[NSNumber numberWithUnsignedLongLong:totalOut],
										@"totalout",
										[NSNumber numberWithDouble:peak],
										@"peak",
										kNetStatsPPPSource,
										kNetStatsSourceKey,
										nil]
								forKey:interfaceName];
				} else {
					NSNumber *totalIn = oldStats ? [oldStats objectForKey:@"totalin"] : [pppStats objectForKey:@"inBytes"];
					NSNumber *totalOut = oldStats ? [oldStats objectForKey:@"totalout"] : [pppStats objectForKey:@"outBytes"];
					NSNumber *peak = oldStats ? [oldStats objectForKey:@"peak"] : @0.0;
					[newStats setObject:[NSDictionary dictionaryWithObjectsAndKeys:
											[pppStats objectForKey:@"inBytes"],
											@"ifin",
											[pppStats objectForKey:@"outBytes"],
											@"ifout",
											@0,
											@"deltain",
											@0,
											@"deltaout",
											totalIn,
											@"totalin",
											totalOut,
											@"totalout",
											// No deltas since that would make
											// first sample artificially large
											peak,
											@"peak",
											kNetStatsPPPSource,
											kNetStatsSourceKey,
											nil]
								 forKey:interfaceName];
				}
			} else if (oldStats) {
				NSMutableDictionary *idleStats = [oldStats mutableCopy];
				idleStats[@"deltain"] = @0;
				idleStats[@"deltaout"] = @0;
				idleStats[kNetStatsSourceKey] = kNetStatsPPPIdleSource;
				newStats[interfaceName] = idleStats;
			}
		}
		if (!handledAsPPP) {
			// Not a PPP connection, or PPP status was unavailable.
			if (oldStats && [[oldStats objectForKey:kNetStatsSourceKey] isEqualToString:kNetStatsSysctlSource]) {
					uint64_t lastTotalIn = [[oldStats objectForKey:@"totalin"] unsignedLongLongValue];
					uint64_t lastTotalOut = [[oldStats objectForKey:@"totalout"] unsignedLongLongValue];
					// New totals
					uint64_t totalIn = 0, totalOut = 0;
					uint64_t ifIn = ifmsg->ifm_data.ifi_ibytes;
					uint64_t ifOut = ifmsg->ifm_data.ifi_obytes;
					uint64_t lastifIn = [[oldStats objectForKey:@"ifin"] unsignedLongLongValue];
					uint64_t lastifOut = [[oldStats objectForKey:@"ifout"] unsignedLongLongValue];
					if (lastifIn > ifIn) {
						totalIn = lastTotalIn + ifIn;
					} else {
						totalIn = lastTotalIn + (ifIn - lastifIn);
					}
					if (lastifOut > ifOut) {
						totalOut = lastTotalOut + ifOut;
					} else {
						totalOut = lastTotalOut + (ifOut - lastifOut);
					}
				// New deltas (64-bit overflow guard, full paranoia)
				uint64_t deltaIn = (totalIn > lastTotalIn) ? (totalIn - lastTotalIn) : 0;
				uint64_t deltaOut = (totalOut > lastTotalOut) ? (totalOut - lastTotalOut) : 0;
				// Peak
				double peak = [[oldStats objectForKey:@"peak"] doubleValue];
				if (sampleInterval > 0) {
					if (peak < (deltaIn / sampleInterval)) peak = deltaIn / sampleInterval;
					if (peak < (deltaOut / sampleInterval)) peak = deltaOut / sampleInterval;
					}
					[newStats setObject:[NSDictionary dictionaryWithObjectsAndKeys:
											[NSNumber numberWithUnsignedLongLong:ifIn],
											@"ifin",
											[NSNumber numberWithUnsignedLongLong:ifOut],
											@"ifout",
										[NSNumber numberWithUnsignedLongLong:deltaIn],
										@"deltain",
										[NSNumber numberWithUnsignedLongLong:deltaOut],
										@"deltaout",
										[NSNumber numberWithUnsignedLongLong:totalIn],
										@"totalin",
										[NSNumber numberWithUnsignedLongLong:totalOut],
										@"totalout",
										[NSNumber numberWithDouble:peak],
										@"peak",
										kNetStatsSysctlSource,
										kNetStatsSourceKey,
										nil]
							forKey:interfaceName];
				} else {
					NSNumber *totalIn = oldStats ? [oldStats objectForKey:@"totalin"] : [NSNumber numberWithUnsignedLongLong:ifmsg->ifm_data.ifi_ibytes];
					NSNumber *totalOut = oldStats ? [oldStats objectForKey:@"totalout"] : [NSNumber numberWithUnsignedLongLong:ifmsg->ifm_data.ifi_obytes];
					NSNumber *peak = oldStats ? [oldStats objectForKey:@"peak"] : @0.0;
					[newStats setObject:[NSDictionary dictionaryWithObjectsAndKeys:
											// Paranoia, is this where the neg numbers came from?
											[NSNumber numberWithUnsignedLongLong:ifmsg->ifm_data.ifi_ibytes],
											@"ifin",
											[NSNumber numberWithUnsignedLongLong:ifmsg->ifm_data.ifi_obytes],
											@"ifout",
										@0,
										@"deltain",
										@0,
										@"deltaout",
										totalIn,
										@"totalin",
										totalOut,
										@"totalout",
										peak,
										@"peak",
										kNetStatsSysctlSource,
										kNetStatsSourceKey,
										nil]
						forKey:interfaceName];
			}
		}

		// Continue on
		currentData += ifmsg->ifm_msglen;
	}

	// Store and return
	lastData = newStats;
	return newStats;

} // netStatsForInterval

@end
