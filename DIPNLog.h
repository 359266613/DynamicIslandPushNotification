#ifndef DIPN_LOG_H
#define DIPN_LOG_H

#define DIPN_LOG_TAG @"[DIPN]"

#ifndef DIPN_LOG_LEVEL
// 0: off, 1: error, 2: warn, 3: info
#define DIPN_LOG_LEVEL 2
#endif

#if DIPN_LOG_LEVEL >= 3
#define DIPNLogInfo(fmt, ...) NSLog((DIPN_LOG_TAG @" [INFO] " fmt), ##__VA_ARGS__)
#else
#define DIPNLogInfo(fmt, ...)
#endif

#if DIPN_LOG_LEVEL >= 2
#define DIPNLogWarn(fmt, ...) NSLog((DIPN_LOG_TAG @" [WARN] " fmt), ##__VA_ARGS__)
#else
#define DIPNLogWarn(fmt, ...)
#endif

#if DIPN_LOG_LEVEL >= 1
#define DIPNLogError(fmt, ...) NSLog((DIPN_LOG_TAG @" [ERROR] " fmt), ##__VA_ARGS__)
#else
#define DIPNLogError(fmt, ...)
#endif

#endif
