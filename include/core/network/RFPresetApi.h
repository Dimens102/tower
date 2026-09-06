#pragma once

#include <string>

struct RFPresetApiResponse
{
    int status = 200;
    std::string statusText = "OK";
    std::string jsonBody;
};

RFPresetApiResponse saveRFPresetsFromJson(const std::string& body);
RFPresetApiResponse executeRFPresetFromJson(const std::string& body);
