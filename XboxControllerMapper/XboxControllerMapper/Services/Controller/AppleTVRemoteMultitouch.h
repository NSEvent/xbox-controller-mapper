#ifndef AppleTVRemoteMultitouch_h
#define AppleTVRemoteMultitouch_h

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*CKAppleTVRemoteMultitouchCallback)(void *context, float x, float y, bool touching);

bool CKAppleTVRemoteMultitouchStart(void *context, CKAppleTVRemoteMultitouchCallback callback);
void CKAppleTVRemoteMultitouchStop(void);
bool CKAppleTVRemoteMultitouchIsRunning(void);

#ifdef __cplusplus
}
#endif

#endif /* AppleTVRemoteMultitouch_h */
