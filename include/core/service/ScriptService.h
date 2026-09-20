#pragma once
#include "nlohmann/json.hpp"
#include <string>
class ScriptService {
public:
    static nlohmann::json list();
    static void save(const nlohmann::json& script);
    static void remove(const std::string& id);
    static bool run(const std::string& id, std::string& message);
    static bool wake(const std::string& mac,const std::string& broadcast,std::string& message,int port=9);
};
