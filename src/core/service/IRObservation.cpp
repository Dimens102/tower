#include "core/service/IRTriggerService.h"
#include "core/service/DeviceStateService.h"
#include "core/logging/Logger.h"
#include "devices/device_database.h"
#include "devices/ir/ir_database.h"
#include "devices/ir/ir_analyzer.h"
#include "devices/ir/ir_receiver_array.h"
#include <linux/lirc.h>
#include <sys/ioctl.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <set>
#include <cmath>

namespace {
struct Known {std::string key,command;unsigned khz;std::vector<unsigned> frame;IRDecode decoded;bool decodedOk;};
std::vector<Known> loadKnown(){
    std::vector<Known> result;DeviceDatabase db;IRDatabase ir;
    for(const auto& id:db.listDevices()){
        Device device;if(!db.loadDevice(id,device)||!device.enabled)continue;
        for(const auto& c:device.commands){
            if(!c.enabled||c.transport!=TransportType::IR)continue;
            auto remote=c.transportDevice.empty()?id:c.transportDevice;auto command=c.transportCommand.empty()?c.id:c.transportCommand;
            IRCode code;if(!ir.load(remote,command,code))continue;
            std::vector<unsigned> frame;
            auto append=[&]{if(frame.size()>6){Known item{"ir:"+remote,command,code.carrierKhz,frame,{},false};item.decodedOk=IRAnalyzer::decodeDurations(frame,item.decoded);result.push_back(item);}frame.clear();};
            for(std::size_t i=0;i<code.pulses.size();++i){if(i%2&&code.pulses[i]>=10000)append();else frame.push_back(code.pulses[i]);}append();
        }
    }
    return result;
}
bool matches(const Known& known,const std::vector<unsigned>& frame,const IRDecode& decoded,bool valid){
    if(known.decodedOk&&valid)return known.decoded.protocol==decoded.protocol&&known.decoded.address==decoded.address&&known.decoded.command==decoded.command;
    if(frame.size()!=known.frame.size())return false;
    double sum=0;for(std::size_t i=0;i<frame.size();++i){double err=std::abs(double(frame[i])-known.frame[i])/std::max(1U,known.frame[i]);if(err>0.28)return false;sum+=err;}
    return sum/frame.size()<0.14;
}
}
void IRTriggerService::observationLoop(){
    struct Receiver {int fd;int khz;std::vector<unsigned> frame;bool pulse=true;bool ignored=false;};
    std::size_t previousReceivers=999,previousKnown=999;
    while(running_){
        std::vector<Receiver> receivers;
        try{
            auto known=loadKnown();
            for(const auto& item:IRReceiverArray().discover())if(item.available()){
                int fd=::open(item.lircDevice.c_str(),O_RDONLY|O_NONBLOCK);if(fd<0)continue;
                unsigned mode=LIRC_MODE_MODE2;(void)::ioctl(fd,LIRC_SET_REC_MODE,&mode);
                receivers.push_back({fd,item.receiver.nominalCarrierKhz,{},true,false});
            }
            if(previousReceivers!=receivers.size()||previousKnown!=known.size()){
                Logger::info("IR observation","Monitoring "+std::to_string(receivers.size())+" receivers; "+std::to_string(known.size())+" learned frames");previousReceivers=receivers.size();previousKnown=known.size();
            }
            auto refresh=std::chrono::steady_clock::now()+std::chrono::seconds(30);
            while(running_&&std::chrono::steady_clock::now()<refresh){
                std::vector<pollfd> descriptors;for(const auto& r:receivers)descriptors.push_back({r.fd,POLLIN,0});
                if(::poll(descriptors.data(),descriptors.size(),100)<=0)continue;
                for(std::size_t i=0;i<receivers.size();++i){
                    if(!(descriptors[i].revents&POLLIN))continue;
                    auto& r=receivers[i];lirc_t sample;
                    // Bounded drain prevents a noisy receiver starving the others.
                    for(int n=0;n<1024&&::read(r.fd,&sample,sizeof(sample))==sizeof(sample);++n){
                        bool ignore=DeviceStateService::receptionSuppressed()||std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count()<ignoreUntilMilliseconds_.load();
                        auto mode=sample&LIRC_MODE2_MASK;unsigned duration=sample&LIRC_VALUE_MASK;
                        if(mode==LIRC_MODE2_TIMEOUT||(mode==LIRC_MODE2_SPACE&&duration>=10000)){
                            if(!ignore&&!r.ignored&&r.frame.size()>6){
                                IRDecode decoded;bool valid=IRAnalyzer::decodeDurations(r.frame,decoded);
                                std::set<std::pair<std::string,std::string>> found;
                                for(const auto& k:known)if((!k.khz||std::abs(int(k.khz)-r.khz)<=3)&&matches(k,r.frame,decoded,valid))found.insert({k.key,k.command});
                                // Do not guess when several device commands share a signal.
                                if(found.size()==1)DeviceStateService::observe(found.begin()->first,found.begin()->second);
                            }
                            r.frame.clear();r.pulse=true;r.ignored=false;continue;
                        }
                        if(mode!=LIRC_MODE2_PULSE&&mode!=LIRC_MODE2_SPACE)continue;
                        bool pulse=mode==LIRC_MODE2_PULSE;
                        if(pulse!=r.pulse){r.frame.clear();r.pulse=true;r.ignored=false;if(!pulse)continue;}
                        r.ignored=r.ignored||ignore;r.frame.push_back(duration);r.pulse=!r.pulse;
                        if(r.frame.size()>512){r.frame.clear();r.pulse=true;r.ignored=true;}
                    }
                }
            }
        }catch(const std::exception& e){Logger::warning("IR observation",e.what());}
        for(const auto& r:receivers)::close(r.fd);
        if(receivers.empty())for(int n=0;n<20&&running_;++n)std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
}
