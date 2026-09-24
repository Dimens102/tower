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
#include <random>
#include <ctime>
extern char** environ;
using nlohmann::json;
namespace {
std::mutex scriptsMutex;
const std::filesystem::path path="data/control/scripts.json";
json readScripts(){if(!std::filesystem::exists(path))return json::array();std::ifstream in(path);json d;in>>d;if(!d.is_array())throw std::runtime_error("Invalid scripts file");return d;}
void writeScripts(const json& d){std::filesystem::create_directories(path.parent_path());auto tmp=path.string()+".tmp";{std::ofstream out(tmp);out<<d.dump(2)<<'\n';out.flush();if(!out)throw std::runtime_error("Cannot save scripts");}std::filesystem::rename(tmp,path);}
const std::filesystem::path jobPath="data/control/windows_jobs.json";
json readJobs(){if(!std::filesystem::exists(jobPath))return json::array();std::ifstream in(jobPath);json d;in>>d;if(!d.is_array())throw std::runtime_error("Invalid Windows jobs file");return d;}
void writeJobs(const json& d){std::filesystem::create_directories(jobPath.parent_path());auto tmp=jobPath.string()+".tmp";{std::ofstream out(tmp);out<<d.dump(2)<<'\n';out.flush();if(!out)throw std::runtime_error("Cannot save Windows job");}std::filesystem::rename(tmp,jobPath);}
std::string jobId(){std::random_device random;std::string id;const char* digits="0123456789abcdef";for(int i=0;i<32;++i)id+=digits[random()%16];return id;}
void expireJobs(json& jobs){auto now=std::time(nullptr);for(auto& job:jobs){if(job.value("status","")=="queued"&&now>job.value("expires",0LL))job["status"]="expired";if(job.value("status","")=="running"&&now>job.value("started",0LL)+job.value("timeout_seconds",15)+30){job["status"]="unknown";job["message"]="Worker did not report completion; not retried";}}}
}
json ScriptService::jobs(){std::lock_guard lock(scriptsMutex);auto d=readJobs();expireJobs(d);writeJobs(d);for(auto& j:d)j.erase("body");return d;}
json ScriptService::claim(const std::string& target){
    std::lock_guard lock(scriptsMutex);auto d=readJobs();expireJobs(d);json found=nullptr;
    for(auto& job:d)if(job.value("status","")=="queued"&&job.value("target","")==target){job["status"]="running";job["started"]=std::time(nullptr);found=job;break;}
    writeJobs(d);return found;
}
void ScriptService::complete(const json& result){
    std::lock_guard lock(scriptsMutex);auto d=readJobs();
    for(auto& job:d)if(job.at("id")==result.at("id")&&job.at("target")==result.at("target")&&job.value("status","")=="running"){
        job["status"]=result.value("ok",false)?"completed":"failed";job["message"]=result.value("message","").substr(0,4096);job["finished"]=std::time(nullptr);job.erase("body");writeJobs(d);return;
    }
    throw std::runtime_error("Running Windows job not found for this target");
}
json ScriptService::list(){std::lock_guard lock(scriptsMutex);return readScripts();}
void ScriptService::save(const json& s){
    std::lock_guard lock(scriptsMutex);
    if(!std::regex_match(s.value("id",""),std::regex("[A-Za-z0-9_-]{1,80}"))||s.value("name","").empty())throw std::runtime_error("Script needs an ID and name");
    auto kind=s.value("kind","bash");
    if(kind!="bash"&&kind!="wol"&&kind!="powershell")throw std::runtime_error("Choose Bash, Windows PowerShell or Wake-on-LAN");
    if(kind=="powershell"&&(s.value("target","").empty()||s.value("target","").size()>160))throw std::runtime_error("Select the Windows worker target");
    auto windowMode=s.value("window_mode","visible");
    if(kind=="powershell"&&windowMode!="visible"&&windowMode!="hidden")throw std::runtime_error("Windows window mode must be visible or hidden");
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
    int enabled=1;int sent=0;
    if(setsockopt(fd,SOL_SOCKET,SO_BROADCAST,&enabled,sizeof(enabled))==0){
        for(int attempt=0;attempt<3;++attempt){
            if(sendto(fd,packet,sizeof(packet),0,reinterpret_cast<sockaddr*>(&destination),sizeof(destination))==sizeof(packet))++sent;
            if(attempt<2)std::this_thread::sleep_for(std::chrono::milliseconds(75));
        }
    }
    close(fd);
    const bool ok=sent==3;
    message=ok
        ?"Wake packet sent 3 times to "+broadcast+" for "+mac+"; PC power state is not confirmed"
        :"Wake packet delivery failed ("+std::to_string(sent)+" of 3 sent) to "+broadcast+" for "+mac;
    return ok;
}
bool ScriptService::run(const std::string& id,std::string& message){
    try{
        json script;{std::lock_guard lock(scriptsMutex);for(const auto& s:readScripts())if(s.value("id","")==id){script=s;break;}}
        if(script.is_null())throw std::runtime_error("Saved script not found: "+id);
        if(script.value("kind","bash")=="powershell"){
            std::lock_guard lock(scriptsMutex);auto d=readJobs();expireJobs(d);
            // Retain a bounded history but never discard pending work silently.
            while(d.size()>=100){auto it=std::find_if(d.begin(),d.end(),[](const json& j){return j.value("status","")!="queued"&&j.value("status","")!="running";});if(it==d.end())throw std::runtime_error("Windows queue is full");d.erase(it);}
            json job={{"id",jobId()},{"script",id},{"name",script.value("name",id)},{"target",script.at("target")},{"body",script.value("body","")},{"timeout_seconds",script.value("timeout_seconds",15)},{"window_mode",script.value("window_mode","visible")},{"status","queued"},{"created",std::time(nullptr)},{"expires",std::time(nullptr)+60}};
            d.push_back(job);writeJobs(d);message="Queued on Windows: "+script.at("target").get<std::string>()+" (expires in 60 seconds if offline)";return true;
        }
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
