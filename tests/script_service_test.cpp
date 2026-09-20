#include "core/service/ScriptService.h"
#include <cassert>
#include <filesystem>
#include <iostream>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
using nlohmann::json;
int main(){
    std::string path=(std::filesystem::temp_directory_path()/"tower-script-test-XXXXXX").string();assert(mkdtemp(path.data()));std::filesystem::current_path(path);
    json script={{"id","example"},{"name","Example"},{"kind","bash"},{"body","printf 'hello world\\n'\r\n"},{"timeout_seconds",1}};
    ScriptService::save(script);std::string message;assert(ScriptService::run("example",message));assert(message.find("hello world")!=std::string::npos);
    script["body"]="exit 7";ScriptService::save(script);assert(!ScriptService::run("example",message));
    script["body"]="sleep 30";ScriptService::save(script);assert(!ScriptService::run("example",message));assert(message=="Script timed out");
    assert(!ScriptService::wake("invalid","127.0.0.1",message));
    int fd=socket(AF_INET,SOCK_DGRAM,0);assert(fd>=0);sockaddr_in addr{};addr.sin_family=AF_INET;addr.sin_port=0;inet_pton(AF_INET,"127.0.0.1",&addr.sin_addr);
    assert(bind(fd,reinterpret_cast<sockaddr*>(&addr),sizeof(addr))==0);timeval timeout{2,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    socklen_t length=sizeof(addr);assert(getsockname(fd,reinterpret_cast<sockaddr*>(&addr),&length)==0);
    assert(ScriptService::wake("02:11:22:33:44:55","127.0.0.1",message,ntohs(addr.sin_port)));unsigned char packet[102];assert(recv(fd,packet,102,0)==102);close(fd);
    for(int i=0;i<6;i++)assert(packet[i]==255);const unsigned char expected[]={2,17,34,51,68,85};for(int j=0;j<16;j++)for(int i=0;i<6;i++)assert(packet[6+j*6+i]==expected[i]);
    ScriptService::remove("example");assert(ScriptService::list().empty());std::filesystem::remove_all(path);std::cout<<"Script and Wake-on-LAN tests passed\n";
}
