#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif
typedef struct CSFCaptchaSession CSFCaptchaSession;
CSFCaptchaSession *CSFCaptchaCreate(const char *model_path, char **error);
float *CSFCaptchaRun(CSFCaptchaSession *session, const float *input, size_t count,
                    size_t *columns, char **error);
void CSFCaptchaDestroy(CSFCaptchaSession *session);
void CSFCaptchaFree(void *buffer);
#ifdef __cplusplus
}
#endif
