#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <notify.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

// ---- 熱レベル (notify: com.apple.system.thermalpressurelevel) ----

int tb_thermal_level(void) {
    static int token = -1;
    if (token < 0 &&
        notify_register_check("com.apple.system.thermalpressurelevel", &token) != NOTIFY_STATUS_OK)
        return -1;
    uint64_t s = 0;
    return notify_get_state(token, &s) == NOTIFY_STATUS_OK ? (int)s : -1;
}

// ---- AppleSMC ----

typedef struct { char major, minor, build, reserved[1]; unsigned short release; } SMCVersion;
typedef struct { unsigned short version, length; unsigned int cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { unsigned int dataSize, dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    unsigned int key; SMCVersion vers; SMCPLimitData pLimitData; SMCKeyInfo keyInfo;
    char result, status, data8; unsigned int data32; unsigned char bytes[32];
} SMCData;

static io_connect_t gConn;
static int gOpen;
#define TAMAX 64
static char gTa[TAMAX][5];
static int gTaN;

static int smcCall(SMCData *in, SMCData *out) {
    size_t s = sizeof(SMCData);
    return IOConnectCallStructMethod(gConn, 2, in, sizeof(SMCData), out, &s);
}
static unsigned int k2i(const char *k) {
    return ((unsigned char)k[0] << 24) | ((unsigned char)k[1] << 16) |
           ((unsigned char)k[2] << 8) | (unsigned char)k[3];
}
static int validTemp(double v) { return v >= -100 && v <= 130; }

int tb_smc_init(void) {
    io_service_t sv = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!sv || IOServiceOpen(sv, mach_task_self(), 0, &gConn)) return -1;
    gOpen = 1;
    // 起動時に一度だけ全キーを列挙し、"Ta" で始まるキー名を覚える
    SMCData in = {0}, out = {0};
    in.key = k2i("#KEY"); in.data8 = 9;
    if (smcCall(&in, &out)) return 0;
    memset(&in, 0, sizeof in);
    in.key = k2i("#KEY"); in.keyInfo.dataSize = 4; in.data8 = 5;
    if (smcCall(&in, &out)) return 0;
    unsigned int n = (out.bytes[0] << 24) | (out.bytes[1] << 16) | (out.bytes[2] << 8) | out.bytes[3];
    if (n > 4096) n = 4096;
    for (unsigned int i = 0; i < n && gTaN < TAMAX; i++) {
        memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
        in.data8 = 8; in.data32 = i;
        if (smcCall(&in, &out)) continue;
        char ks[5] = {(char)(out.key >> 24), (char)(out.key >> 16), (char)(out.key >> 8), (char)out.key, 0};
        if (ks[0] == 'T' && ks[1] == 'a') { memcpy(gTa[gTaN], ks, 5); gTaN++; }
    }
    return 0;
}

double tb_smc_read(const char *key) {
    if (!gOpen || !key || strlen(key) != 4) return NAN;
    SMCData in = {0}, out = {0};
    in.key = k2i(key); in.data8 = 9;
    if (smcCall(&in, &out) || out.result != 0 ||
        out.keyInfo.dataType != k2i("flt ") || out.keyInfo.dataSize != 4) return NAN;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = k2i(key); in.keyInfo.dataSize = 4; in.data8 = 5;
    if (smcCall(&in, &out) || out.result != 0) return NAN;
    float f; memcpy(&f, out.bytes, 4);
    return validTemp(f) ? f : NAN;
}

int tb_smc_ta_count(void) { return gTaN; }
const char *tb_smc_ta_key(int i) { return (i >= 0 && i < gTaN) ? gTa[i] : ""; }

double tb_smc_ta_max(void) {
    double m = NAN;
    for (int i = 0; i < gTaN; i++) {
        double v = tb_smc_read(gTa[i]);
        if (!isnan(v) && (isnan(m) || v > m)) m = v;
    }
    return m;
}

// ---- HID 温度センサー (IOHIDEventSystem) ----

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef, CFDictionaryRef);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
extern double IOHIDEventGetFloatValue(IOHIDEventRef, int32_t);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef, CFStringRef);

static double hidScan(const char *prefix, int dump) {
    @autoreleasepool {
        IOHIDEventSystemClientRef c = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!c) return NAN;
        IOHIDEventSystemClientSetMatching(c, (__bridge CFDictionaryRef)
            @{@"PrimaryUsagePage": @0xff00, @"PrimaryUsage": @5});
        NSArray *services = CFBridgingRelease(IOHIDEventSystemClientCopyServices(c));
        NSString *want = prefix ? [NSString stringWithUTF8String:prefix] : nil;
        double m = NAN;
        for (id x in services) {
            IOHIDServiceClientRef sc = (__bridge IOHIDServiceClientRef)x;
            NSString *n = CFBridgingRelease(IOHIDServiceClientCopyProperty(sc, CFSTR("Product")));
            IOHIDEventRef e = IOHIDServiceClientCopyEvent(sc, 15, 0, 0);
            if (!e) continue;
            double v = IOHIDEventGetFloatValue(e, 15 << 16);
            CFRelease(e);
            if (dump) { printf("%s\t%.1f\n", n ? [n UTF8String] : "?", v); continue; }
            if (!n || ![n hasPrefix:want] || !validTemp(v)) continue;
            if (isnan(m) || v > m) m = v;
        }
        CFRelease(c);
        return m;
    }
}

double tb_hid_max(const char *prefix) { return hidScan(prefix, 0); }
void tb_hid_list(void) { (void)hidScan(NULL, 1); }
