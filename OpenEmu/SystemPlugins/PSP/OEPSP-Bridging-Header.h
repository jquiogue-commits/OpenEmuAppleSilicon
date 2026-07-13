//
//  OEPSP-Bridging-Header.h
//  Exposes zlib (CSO decompression in the system controller) and the responder-client
//  protocol/button enum to the Swift PSP plugin sources.
//

@import OpenEmuSystem;
#import <zlib.h>
#import "OEPSPSystemResponderClient.h"
