#pragma once

#include <optional>
#include <string>

class HttpClient
{
public:
    std::optional<std::string> get(
        const std::string& url) const;
};