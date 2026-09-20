#include "core/service/ScriptService.h"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <regex>
#include <chrono>
#include <thread>
#include <spawn.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <stdexcept>
#include <cerrno>
extern char** environ;
using nlohmann::json;
namespace {
std::mutex scriptsMutex;
const std::filesystem::path path="data/control/scripts.json";
json readScripts(){if(!std::filesystem::exists(path))return json::array();std::ifstream in(path);json d;in>>d;if(!d.is_array())throw std::runtime_error("Invalid scripts file");return d;}
void writeScripts(const json& d){std::filesystem::create_directories(path.parent_path());auto tmp=path.string()+".tmp";{std::ofstream out(tmp);out<<d.dump(2)<<'\n';out.flush();if(!out)throw std::runtime_error("Cannot save scripts");}std::filesystem::rename(tmp,path);}
}
json ScriptService::list(){std::lock_guard lock(scriptsMutex);return readScripts();}
void ScriptService::save(const json& s){
    std::lock_guard lock(scriptsMutex);
    if(!std::regex_match(s.value("id",""),std::regex("[A-Za-z0-9_-]{1,80}"))||s.value("name","").empty())throw std::runtime_error("Script needs an ID and name");
    auto kind=s.value("kind","bash");
    if(kind!="bash"&&kind!="wol")throw std::runtime_error("Choose Bash or Wake-on-LAN");
    if(s.value("body","").size()>32768)throw std::runtime_error("Script is limited to 32 KB");
    int seconds=s.value("timeout_seconds",15);if(seconds<1||seconds>120)throw std::runtime_error("Timeout must be 1-120 seconds");
    auto d=readScripts();bool found=false;for(auto& item:d)if(item.at("id")==s.at("id")){item=s;found=true;break;}if(!found)d.push_back(s);writeScripts(d);
}
void ScriptService::remove(const std::string& id){std::lock_guard lock(scriptsMutex);auto d=readScripts();d.erase(std::remove_if(d.begin(),d.end(),[&](const auto& s){return s.value("id","")==id;}),d.end());writeScripts(d);}
bool ScriptService::wake(const std::string& mac,const std::string& broadcast,std::string& message,int port){
    if(port<1||port>65535){message="Invalid Wake-on-LAN port";return false;}
    if(!std::regex_match(mac,std::regex("[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}"))){message="Enter a six-byte MAC address";return false;}
    unsigned char packet[102];std::fill(packet,packet+6,0xff);
    for(int i=0;i<6;++i){auto b=std::stoul(mac.substr(i*3,2),nullptr,16);for(int j=0;j<16;++j)packet[6+j*6+i]=b;}
    sockaddr_in destination{};destination.sin_family=AF_INET;destination.sin_port=htons(static_cast<unsigned short>(port));
    if(inet_pton(AF_INET,broadcast.c_str(),&destination.sin_addr)!=1){message="Invalid IPv4 broadcast address";return false;}
    int fd=socket(AF_INET,SOCK_DGRAM,0);if(fd<0){message="Cannot open Wake-on-LAN socket";return false;}
    int enabled=1;bool ok=setsockopt(fd,SOL_SOCKET,SO_BROADCAST,&enabled,sizeof(enabled))==0 && sendto(fd,packet,sizeof(packet),0,reinterpret_cast<sockaddr*>(&destination),sizeof(destination))==sizeof(packet);close(fd);
    message=ok?"Wake packet sent; PC power state is not confirmed":"Wake packet could not be sent";return ok;
}
bool ScriptService::run(const std::string& id,std::string& message){
    try{
        json script;{std::lock_guard lock(scriptsMutex);for(const auto& s:readScripts())if(s.value("id","")==id){script=s;break;}}
        if(script.is_null())throw std::runtime_error("Saved script not found: "+id);
        if(script.value("kind","bash")=="wol")return wake(script.value("mac",""),script.value("broadcast","255.255.255.255"),message,script.value("port",9));
        // No shell interpolation of names/paths; body is the explicitly saved script.
        char inputName[]="/tmp/tower-script-XXXXXX", outputName[]="/tmp/tower-script-output-XXXXXX";
        int input=mkstemp(inputName),output=mkstemp(outputName);
        struct Files{int a,b;const char *p,*q;~Files(){if(a>=0)close(a);if(b>=0)close(b);unlink(p);unlink(q);}} files{input,output,inputName,outputName};
        if(input<0||output<0)throw std::runtime_error("Cannot create script files");
        auto body=script.value("body","");body.erase(std::remove(body.begin(),body.end(),'\r'),body.end());
        std::size_t offset=0;while(offset<body.size()){auto n=write(input,body.data()+offset,body.size()-offset);if(n<=0)throw std::runtime_error("Cannot write script");offset+=n;}
        // Limit output to 64 KiB even for a runaway script. The service's user is retained.
        std::string command="ulimit -f 128; source \"$1\"";
        char* argv[]={const_cast<char*>("bash"),const_cast<char*>("-c"),command.data(),const_cast<char*>("tower-script"),inputName,nullptr};
        posix_spawn_file_actions_t actions;posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_addopen(&actions,STDIN_FILENO,"/dev/null",O_RDONLY,0);
        posix_spawn_file_actions_adddup2(&actions,output,STDOUT_FILENO);posix_spawn_file_actions_adddup2(&actions,output,STDERR_FILENO);
        posix_spawn_file_actions_addclose(&actions,input);posix_spawn_file_actions_addclose(&actions,output);
        posix_spawnattr_t attr;posix_spawnattr_init(&attr);posix_spawnattr_setflags(&attr,POSIX_SPAWN_SETPGROUP);posix_spawnattr_setpgroup(&attr,0);
        pid_t pid;int result=posix_spawn(&pid,"/bin/bash",&actions,&attr,argv,environ);
        posix_spawn_file_actions_destroy(&actions);posix_spawnattr_destroy(&attr);
        if(result!=0)throw std::runtime_error("Could not start Bash");
        auto end=std::chrono::steady_clock::now()+std::chrono::seconds(script.value("timeout_seconds",15));int status=0;bool timedOut=false;
        for(;;){auto waited=waitpid(pid,&status,WNOHANG);if(waited==pid)break;if(waited<0&&errno!=EINTR){kill(-pid,SIGKILL);throw std::runtime_error("Cannot read script exit status");}if(std::chrono::steady_clock::now()>=end){timedOut=true;kill(-pid,SIGKILL);while(waitpid(pid,&status,0)<0&&errno==EINTR){}break;}std::this_thread::sleep_for(std::chrono::milliseconds(50));}
        kill(-pid,SIGKILL); // Saved scripts are finite jobs, not daemon launchers.
        std::ifstream out(outputName);char text[4097]{};out.read(text,4096);
        bool ok=!timedOut&&WIFEXITED(status)&&WEXITSTATUS(status)==0;
        message=timedOut?"Script timed out":ok?"Script completed":"Script failed";
        if(out.gcount()>0)message+="\n"+std::string(text,static_cast<std::size_t>(out.gcount()));return ok;
    }catch(const std::exception& e){message=e.what();return false;}
}
