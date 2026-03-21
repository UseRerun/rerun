#ifndef SQLITE_VEC_H
#define SQLITE_VEC_H

#ifndef SQLITE_CORE
#include "sqlite3ext.h"
#else
#include "sqlite3.h"
#endif

#ifdef SQLITE_VEC_STATIC
  #define SQLITE_VEC_API
#else
  #ifdef _WIN32
    #define SQLITE_VEC_API __declspec(dllexport)
  #else
    #define SQLITE_VEC_API
  #endif
#endif

#define SQLITE_VEC_VERSION "v0.1.7"
// TODO rm
#define SQLITE_VEC_DATE "2026-03-17T07:41:55Z+0000"
#define SQLITE_VEC_SOURCE "633eecf5067ab12ef331b3c4500c765f8e6d6da0"


#define SQLITE_VEC_VERSION_MAJOR 0
#define SQLITE_VEC_VERSION_MINOR 1
#define SQLITE_VEC_VERSION_PATCH 7

#ifdef __cplusplus
extern "C" {
#endif

SQLITE_VEC_API int sqlite3_vec_init(sqlite3 *db, char **pzErrMsg,
                  const sqlite3_api_routines *pApi);

#ifdef __cplusplus
}  /* end of the 'extern "C"' block */
#endif

#endif /* ifndef SQLITE_VEC_H */
