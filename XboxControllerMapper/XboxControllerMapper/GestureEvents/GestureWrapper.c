//
//  GestureWrapper.c
//  XboxControllerMapper
//
//  Swift-friendly wrapper for TouchEvents gesture creation
//

#include "GestureWrapper.h"
#include "TouchEvents.h"
#include "IOHIDEventTypes.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>

bool postMagnifyGestureEvent(double magnification, int phase) {
    // Determine phase constant
    int phaseValue;
    switch (phase) {
        case 0: phaseValue = kIOHIDEventPhaseBegan; break;
        case 1: phaseValue = kIOHIDEventPhaseChanged; break;
        case 2: phaseValue = kIOHIDEventPhaseEnded; break;
        default: phaseValue = kIOHIDEventPhaseChanged; break;
    }

    // Create gesture info dictionary
    int subtype = kTLInfoSubtypeMagnify;
    CFNumberRef subtypeNum = CFNumberCreate(NULL, kCFNumberIntType, &subtype);
    CFNumberRef phaseNum = CFNumberCreate(NULL, kCFNumberIntType, &phaseValue);
    CFNumberRef magNum = CFNumberCreate(NULL, kCFNumberDoubleType, &magnification);

    const void *keys[] = { kTLInfoKeyGestureSubtype, kTLInfoKeyGesturePhase, kTLInfoKeyMagnification };
    const void *values[] = { subtypeNum, phaseNum, magNum };

    CFDictionaryRef info = CFDictionaryCreate(
        NULL,
        keys,
        values,
        3,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );

    // Create empty touches array
    CFArrayRef touches = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);

    // Create the gesture event using Hammerspoon's implementation
    CGEventRef event = tl_CGEventCreateFromGesture(info, touches);

    // Clean up
    CFRelease(subtypeNum);
    CFRelease(phaseNum);
    CFRelease(magNum);
    CFRelease(info);
    CFRelease(touches);

    if (!event) {
        return false;
    }

    // Post the event
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);

    return true;
}
