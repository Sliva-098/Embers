// Пустое Cocoa-приложение для Embers.
// Discord на macOS видит только приложения из NSWorkspace.runningApplications,
// у которых есть окно, поэтому держим одно невидимое окно 1×1, которое не ловит клики.
#import <Cocoa/Cocoa.h>
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1, 1)
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        w.opaque = NO;
        w.backgroundColor = NSColor.clearColor;
        w.ignoresMouseEvents = YES;
        w.hasShadow = NO;
        w.level = NSNormalWindowLevel;
        w.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
        [w orderFrontRegardless];
        [NSApp run];
    }
    return 0;
}
