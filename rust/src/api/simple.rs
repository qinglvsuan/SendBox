use std::collections::{HashMap, HashSet};
use std::sync::RwLock;
use std::path::PathBuf;
use once_cell::sync::Lazy;
use crate::frb_generated::StreamSink;
use uuid::Uuid;
use tokio::fs::File;
use tokio::runtime::Runtime;
use futures_util::StreamExt;

use crate::server::run_server;
use crate::mdns::MdnsService;

#[derive(Clone, Debug)]
pub enum StagedItemType {
    File,
    Text,
}

#[derive(Clone, Debug)]
pub struct StagedItem {
    pub id: String,
    pub name: String,
    pub item_type: StagedItemType,
    pub path: Option<String>,
    pub text: Option<String>,
    pub size: u64,
}

#[derive(Clone, Debug)]
pub struct DiscoveredService {
    pub id: String,
    pub node_name: String,
    pub ip: String,
    pub port: u16,
}

#[derive(Clone, Debug)]
pub struct UploadRequest {
    pub id: String,
    pub name: String,
    pub size: u64,
}

// Global shared state
pub static STAGED_ITEMS: Lazy<RwLock<HashMap<String, StagedItem>>> = Lazy::new(|| RwLock::new(HashMap::new()));
pub static RECEIVED_ITEMS: Lazy<RwLock<HashMap<String, StagedItem>>> = Lazy::new(|| RwLock::new(HashMap::new()));
pub static NODE_NAME: Lazy<RwLock<String>> = Lazy::new(|| RwLock::new("SendBoxNode".to_string()));

static SERVER_SHUTDOWN_TX: Lazy<RwLock<Option<tokio::sync::oneshot::Sender<()>>>> = Lazy::new(|| RwLock::new(None));
static MDNS_SERVICE: Lazy<RwLock<Option<MdnsService>>> = Lazy::new(|| RwLock::new(None));
static MDNS_DISCOVERY_SERVICE: Lazy<RwLock<Option<MdnsService>>> = Lazy::new(|| RwLock::new(None));
pub static CACHE_DIR: Lazy<RwLock<Option<String>>> = Lazy::new(|| RwLock::new(None));

pub static PENDING_UPLOADS: Lazy<RwLock<HashMap<String, tokio::sync::oneshot::Sender<bool>>>> = Lazy::new(|| RwLock::new(HashMap::new()));
pub static APPROVED_TOKENS: Lazy<RwLock<HashSet<String>>> = Lazy::new(|| RwLock::new(HashSet::new()));
pub static UPLOAD_REQUEST_SINK: Lazy<RwLock<Option<StreamSink<UploadRequest>>>> = Lazy::new(|| RwLock::new(None));

/// A dedicated multi-threaded Tokio runtime that lives for the entire process lifetime.
/// FFI calls from Dart arrive on threads without any ambient reactor, so all async
/// work must be dispatched through this runtime.
static TOKIO_RUNTIME: Lazy<Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("Failed to build global Tokio runtime")
});

#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

pub fn init_core(temp_dir: String) {
    let mut guard = CACHE_DIR.write().unwrap_or_else(|e| e.into_inner());
    *guard = Some(temp_dir);
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub fn start_server(port: u16, name: String) -> Result<String, String> {
    // 1. Set the node name
    {
        let mut guard = NODE_NAME.write().unwrap_or_else(|e| e.into_inner());
        *guard = name.clone();
    }

    // 2. Stop existing server if running
    let _ = stop_server();

    // 3. Create shutdown channel — must be created inside the runtime so the
    //    oneshot future is associated with our reactor.
    let (tx, rx) = TOKIO_RUNTIME.block_on(async { tokio::sync::oneshot::channel::<()>() });
    {
    let mut guard = SERVER_SHUTDOWN_TX.write().unwrap_or_else(|e| e.into_inner());
        *guard = Some(tx);
    }

    // 4. Spawn the Axum server on the global runtime — this works from any thread.
    let port_clone = port;
    TOKIO_RUNTIME.spawn(async move {
        if let Err(e) = run_server(port_clone, rx).await {
            eprintln!("Axum server error: {}", e);
        }
    });

    // 5. Register with mDNS
    let mdns = MdnsService::new().map_err(|e| e.to_string())?;
    mdns.register(&name, port).map_err(|e| e.to_string())?;
    {
        let mut guard = MDNS_SERVICE.write().unwrap_or_else(|e| e.into_inner());
        *guard = Some(mdns);
    }

    // Return the local IP address
    let local_ip = local_ip_address::local_ip()
        .map(|ip| ip.to_string())
        .unwrap_or_else(|_| "127.0.0.1".to_string());

    Ok(format!("{}:{}", local_ip, port))
}

pub fn stop_server() -> Result<(), String> {
    // 1. Trigger axum shutdown
    {
        let mut guard = SERVER_SHUTDOWN_TX.write().unwrap_or_else(|e| e.into_inner());
        if let Some(tx) = guard.take() {
            let _ = tx.send(());
        }
    }

    // 2. Unregister from mDNS
    {
        let mut guard = MDNS_SERVICE.write().unwrap_or_else(|e| e.into_inner());
        if let Some(mdns) = guard.take() {
            let name = NODE_NAME.read().unwrap_or_else(|e| e.into_inner()).clone();
            let _ = mdns.unregister(&name);
        }
    }

    Ok(())
}

pub fn stage_file(path: String) -> Result<String, String> {
    let path_buf = PathBuf::from(&path);
    if !path_buf.exists() {
        return Err("File does not exist".to_string());
    }

    let name = path_buf
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("file")
        .to_string();

    let metadata = std::fs::metadata(&path_buf).map_err(|e| e.to_string())?;
    let size = metadata.len();

    let id = Uuid::new_v4().to_string();
    let item = StagedItem {
        id: id.clone(),
        name,
        item_type: StagedItemType::File,
        path: Some(path),
        text: None,
        size,
    };

    {
        let mut guard = STAGED_ITEMS.write().unwrap_or_else(|e| e.into_inner());
        guard.insert(id.clone(), item);
    }

    Ok(id)
}

pub fn stage_text(text: String) -> Result<String, String> {
    let display_name = if text.len() > 30 {
        let truncated: String = text.chars().take(15).collect();
        format!("{}...", truncated.replace('\n', " "))
    } else {
        text.replace('\n', " ")
    };
    
    let size = text.len() as u64;
    let id = Uuid::new_v4().to_string();
    let item = StagedItem {
        id: id.clone(),
        name: display_name,
        item_type: StagedItemType::Text,
        path: None,
        text: Some(text),
        size,
    };

    {
        let mut guard = STAGED_ITEMS.write().unwrap_or_else(|e| e.into_inner());
        guard.insert(id.clone(), item);
    }

    Ok(id)
}

pub fn unstage_item(id: String) -> Result<(), String> {
    let mut guard = STAGED_ITEMS.write().unwrap_or_else(|e| e.into_inner());
    if guard.remove(&id).is_some() {
        Ok(())
    } else {
        Err("Item not found".to_string())
    }
}

pub fn get_staged_items() -> Vec<StagedItem> {
    let guard = STAGED_ITEMS.read().unwrap_or_else(|e| e.into_inner());
    guard.values().cloned().collect()
}

pub fn get_received_items() -> Vec<StagedItem> {
    let guard = RECEIVED_ITEMS.read().unwrap_or_else(|e| e.into_inner());
    guard.values().cloned().collect()
}

pub fn remove_received_item(id: String) -> Result<(), String> {
    let mut guard = RECEIVED_ITEMS.write().unwrap_or_else(|e| e.into_inner());
    if let Some(item) = guard.remove(&id) {
        if let Some(path) = item.path {
            let _ = std::fs::remove_file(path);
        }
        Ok(())
    } else {
        Err("Item not found".to_string())
    }
}

pub fn clean_cache() {
    let base_dir = {
        let guard = CACHE_DIR.read().unwrap_or_else(|e| e.into_inner());
        guard.clone()
    };
    
    let mut path = if let Some(dir) = base_dir {
        std::path::PathBuf::from(dir)
    } else {
        std::env::temp_dir()
    };
    
    path.push("sendbox_cache");
    let _ = std::fs::remove_dir_all(&path);
    let mut guard = RECEIVED_ITEMS.write().unwrap_or_else(|e| e.into_inner());
    guard.clear();
}

pub fn start_discovery(sink: StreamSink<DiscoveredService>) -> Result<(), String> {
    let _ = stop_discovery();
    
    let mdns = MdnsService::new().map_err(|e| e.to_string())?;
    mdns.start_discovery(sink).map_err(|e| e.to_string())?;
    
    {
        let mut guard = MDNS_DISCOVERY_SERVICE.write().unwrap_or_else(|e| e.into_inner());
        *guard = Some(mdns);
    }
    
    Ok(())
}

pub fn stop_discovery() -> Result<(), String> {
    let mut guard = MDNS_DISCOVERY_SERVICE.write().unwrap_or_else(|e| e.into_inner());
    *guard = None;
    Ok(())
}

pub fn start_upload_listener(sink: StreamSink<UploadRequest>) -> Result<(), String> {
    let mut guard = UPLOAD_REQUEST_SINK.write().unwrap_or_else(|e| e.into_inner());
    *guard = Some(sink);
    Ok(())
}

pub fn resolve_upload(id: String, accepted: bool) -> Result<(), String> {
    let mut pending = PENDING_UPLOADS.write().unwrap_or_else(|e| e.into_inner());
    if let Some(tx) = pending.remove(&id) {
        let _ = tx.send(accepted);
    }
    Ok(())
}

pub async fn download_file(url: String, save_path: String, sink: StreamSink<f32>) -> Result<(), String> {
    let client = reqwest::Client::new();
    let res = client.get(&url).send().await.map_err(|e| e.to_string())?;

    let total_size = res.content_length().unwrap_or(0);

    let path = PathBuf::from(&save_path);
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent).await.map_err(|e| e.to_string())?;
    }

    let mut file = File::create(&path).await.map_err(|e| e.to_string())?;
    let mut downloaded: u64 = 0;
    let mut stream = res.bytes_stream();

    while let Some(item) = stream.next().await {
        let chunk = item.map_err(|e| e.to_string())?;
        tokio::io::copy(&mut &chunk[..], &mut file).await.map_err(|e| e.to_string())?;
        downloaded += chunk.len() as u64;

        if total_size > 0 {
            let progress = downloaded as f32 / total_size as f32;
            let _ = sink.add(progress);
        }
    }

    let _ = sink.add(1.0);
    Ok(())
}
