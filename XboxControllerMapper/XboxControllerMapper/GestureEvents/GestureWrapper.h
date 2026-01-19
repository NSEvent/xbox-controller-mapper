//
//  GestureWrapper.h
//  XboxControllerMapper
//
//  Swift-friendly wrapper for TouchEvents gesture creation
//

#ifndef GestureWrapper_h
#define GestureWrapper_h

#include <stdbool.h>

/// Post a magnify (pinch) gesture event
/// @param magnification The magnification delta (positive = zoom in, negative = zoom out)
/// @param phase 0 = began, 1 = changed, 2 = ended
/// @return true if successful
bool postMagnifyGestureEvent(double magnification, int phase);

#endif /* GestureWrapper_h */
