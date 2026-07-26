#include "core/network/HttpClient.h"

#include <curl/curl.h>

#include <cstddef>
#include <mutex>
#include <string>

namespace
{
std::once_flag curlInitializationFlag;

void initializeCurl()
{
    curl_global_init(CURL_GLOBAL_DEFAULT);
}

std::size_t writeResponse(
    char* data,
    std::size_t size,
    std::size_t count,
    void* userData)
{
    const std::size_t byteCount = size * count;

    auto* response = static_cast<std::string*>(userData);
    response->append(data, byteCount);

    return byteCount;
}
}

std::optional<std::string> HttpClient::get(
    const std::string& url) const
{
    std::call_once(
        curlInitializationFlag,
        initializeCurl);

    CURL* curl = curl_easy_init();

    if (curl == nullptr)
    {
        return std::nullopt;
    }

    std::string response;

    curl_easy_setopt(
        curl,
        CURLOPT_URL,
        url.c_str());

    curl_easy_setopt(
        curl,
        CURLOPT_WRITEFUNCTION,
        writeResponse);

    curl_easy_setopt(
        curl,
        CURLOPT_WRITEDATA,
        &response);

    curl_easy_setopt(
        curl,
        CURLOPT_FOLLOWLOCATION,
        1L);

    curl_easy_setopt(
        curl,
        CURLOPT_CONNECTTIMEOUT_MS,
        3000L);

    curl_easy_setopt(
        curl,
        CURLOPT_TIMEOUT_MS,
        5000L);

    curl_easy_setopt(
        curl,
        CURLOPT_NOSIGNAL,
        1L);

    const CURLcode result = curl_easy_perform(curl);

    long statusCode = 0;

    if (result == CURLE_OK)
    {
        curl_easy_getinfo(
            curl,
            CURLINFO_RESPONSE_CODE,
            &statusCode);
    }

    curl_easy_cleanup(curl);

    if (result != CURLE_OK)
    {
        return std::nullopt;
    }

    if (statusCode < 200 || statusCode >= 300)
    {
        return std::nullopt;
    }

    return response;
}