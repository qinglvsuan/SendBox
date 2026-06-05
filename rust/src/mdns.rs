use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashMap;
use std::thread;
use crate::frb_generated::StreamSink;

use crate::api::simple::DiscoveredService;

pub struct MdnsService {
    daemon: ServiceDaemon,
}

impl MdnsService {
    pub fn new() -> Result<Self, mdns_sd::Error> {
        let daemon = ServiceDaemon::new()?;
        Ok(Self { daemon })
    }

    pub fn register(&self, node_name: &str, port: u16) -> Result<(), mdns_sd::Error> {
        let service_type = "_localsender._tcp.local.";
        
        let local_ip = match local_ip_address::local_ip() {
            Ok(ip) => ip.to_string(),
            Err(_) => "127.0.0.1".to_string(),
        };

        let mut properties = HashMap::new();
        properties.insert("node_name".to_string(), node_name.to_string());

        // host_name must end with .local.
        let host_name = format!("{}.local.", node_name);

        let service_info = ServiceInfo::new(
            service_type,
            node_name,
            &host_name,
            &local_ip,
            port,
            Some(properties),
        )?;

        self.daemon.register(service_info)?;
        Ok(())
    }

    pub fn unregister(&self, node_name: &str) -> Result<(), mdns_sd::Error> {
        let service_type = "_localsender._tcp.local.";
        self.daemon.unregister(&format!("{}.{}", node_name, service_type))?;
        Ok(())
    }

    pub fn start_discovery(&self, sink: StreamSink<DiscoveredService>) -> Result<(), mdns_sd::Error> {
        let service_type = "_localsender._tcp.local.";
        let receiver = self.daemon.browse(service_type)?;

        thread::spawn(move || {
            while let Ok(event) = receiver.recv() {
                match event {
                    ServiceEvent::ServiceResolved(info) => {
                        let id = info.get_fullname().to_string();
                        let node_name = info.get_property_val_str("node_name")
                            .map(|s| s.to_string())
                            .unwrap_or_else(|| {
                                info.get_fullname()
                                    .split('.')
                                    .next()
                                    .unwrap_or("Unknown")
                                    .to_string()
                            });

                        // Get the first available address
                        let ip_addr = info.get_addresses()
                            .iter()
                            .next()
                            .map(|addr| addr.to_string());

                        if let Some(ip) = ip_addr {
                            let discovered = DiscoveredService {
                                id,
                                node_name,
                                ip,
                                port: info.get_port(),
                            };
                            let _ = sink.add(discovered);
                        }
                    }
                    _ => {}
                }
            }
        });

        Ok(())
    }
}
