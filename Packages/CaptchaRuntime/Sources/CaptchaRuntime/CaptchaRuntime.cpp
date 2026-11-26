#include "CaptchaRuntime.h"
#include <onnxruntime/onnxruntime_cxx_api.h>
#include <array>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <stdexcept>

struct CSFCaptchaSession {
    Ort::Env environment{ORT_LOGGING_LEVEL_ERROR, "Captcha"};
    Ort::Session session{nullptr};

    explicit CSFCaptchaSession(const char *path) {
        Ort::SessionOptions options;
        options.SetIntraOpNumThreads(2);
        options.SetInterOpNumThreads(1);
        options.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
        session = Ort::Session(environment, path, options);
        if (session.GetInputCount() != 1 || session.GetOutputCount() != 1) {
            throw std::runtime_error("Unexpected captcha model inputs or outputs");
        }
    }
};

CSFCaptchaSession *CSFCaptchaCreate(const char *model_path, char **error) {
    if (error) *error = nullptr;
    try {
        return new CSFCaptchaSession(model_path);
    } catch (const std::exception &exception) {
        if (error) *error = strdup(exception.what());
        return nullptr;
    }
}

float *CSFCaptchaRun(CSFCaptchaSession *handle, const float *input, size_t count,
                    size_t *columns, char **error) {
    if (error) *error = nullptr;
    if (columns) *columns = 0;
    try {
        if (!handle || !input || count != 3 * 640 * 640 || !columns) {
            throw std::runtime_error("Invalid captcha input tensor");
        }
        auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        std::array<int64_t, 4> shape{1, 3, 640, 640};
        auto tensor = Ort::Value::CreateTensor<float>(memory, const_cast<float *>(input), count,
                                                     shape.data(), shape.size());
        Ort::AllocatorWithDefaultOptions allocator;
        auto inputName = handle->session.GetInputNameAllocated(0, allocator);
        auto outputName = handle->session.GetOutputNameAllocated(0, allocator);
        const char *inputs[] = {inputName.get()};
        const char *outputs[] = {outputName.get()};
        auto result = handle->session.Run(Ort::RunOptions{nullptr}, inputs, &tensor, 1, outputs, 1);
        auto info = result[0].GetTensorTypeAndShapeInfo();
        auto dimensions = info.GetShape();
        if (info.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT || dimensions.size() != 3 ||
            dimensions[0] != 1 || dimensions[1] != 5 || dimensions[2] <= 0 || dimensions[2] > 100000) {
            throw std::runtime_error("Unexpected captcha output tensor");
        }
        const size_t bytes = info.GetElementCount() * sizeof(float);
        auto buffer = static_cast<float *>(malloc(bytes));
        if (!buffer) throw std::bad_alloc();
        memcpy(buffer, result[0].GetTensorData<float>(), bytes);
        *columns = static_cast<size_t>(dimensions[2]);
        return buffer;
    } catch (const std::exception &exception) {
        if (error) *error = strdup(exception.what());
        return nullptr;
    }
}

void CSFCaptchaDestroy(CSFCaptchaSession *session) { delete session; }
void CSFCaptchaFree(void *buffer) { free(buffer); }
