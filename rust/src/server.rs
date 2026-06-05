use axum::{
    body::Body,
    extract::{Path, Multipart, Query},
    http::{header, StatusCode, Method},
    response::{Html, IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use std::net::SocketAddr;
use std::path::PathBuf;
use tokio::fs::File;
use tokio_util::io::ReaderStream;
use tokio::io::AsyncWriteExt;
use tower_http::cors::{Any, CorsLayer};
use serde::{Serialize, Deserialize};
use uuid::Uuid;

use crate::api::simple::{
    NODE_NAME, RECEIVED_ITEMS, STAGED_ITEMS, CACHE_DIR,
    StagedItem, StagedItemType, PENDING_UPLOADS, APPROVED_TOKENS, UPLOAD_REQUEST_SINK, UploadRequest,
};

#[derive(Serialize)]
struct ServerInfo {
    node_name: String,
    files: Vec<PublicStagedItem>,
}

#[derive(Serialize)]
struct PublicStagedItem {
    id: String,
    name: String,
    item_type: String,
    size: u64,
}

// Handler for /info
async fn get_info() -> impl IntoResponse {
    let name = {
        let guard = NODE_NAME.read().unwrap_or_else(|e| e.into_inner());
        guard.clone()
    };

    let items = {
        let guard = STAGED_ITEMS.read().unwrap_or_else(|e| e.into_inner());
        guard
            .values()
            .map(|item| PublicStagedItem {
                id: item.id.clone(),
                name: item.name.clone(),
                item_type: match item.item_type {
                    StagedItemType::File => "File".to_string(),
                    StagedItemType::Text => "Text".to_string(),
                },
                size: item.size,
            })
            .collect::<Vec<_>>()
    };

    Json(ServerInfo {
        node_name: name,
        files: items,
    })
}

// Handler for /files/:id
async fn download_file(Path(id): Path<String>) -> impl IntoResponse {
    let item_opt = {
        let guard = STAGED_ITEMS.read().unwrap_or_else(|e| e.into_inner());
        guard.get(&id).cloned()
    };

    match item_opt {
        Some(item) => {
            if let (StagedItemType::File, Some(path_str)) = (item.item_type, item.path) {
                let path = PathBuf::from(&path_str);
                if !path.exists() {
                    return Err((StatusCode::NOT_FOUND, "File not found on disk".to_string()));
                }

                let file = match File::open(&path).await {
                    Ok(f) => f,
                    Err(e) => return Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to open file: {}", e))),
                };

                let metadata = match file.metadata().await {
                    Ok(m) => m,
                    Err(e) => return Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to get metadata: {}", e))),
                };

                let stream = ReaderStream::new(file);
                let body = Body::from_stream(stream);

                // Inline file name encoding to handle non-ASCII filenames
                let filename = path.file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("file");
                
                // Percent encode filename for Content-Disposition header
                let encoded_filename = percent_encoding::utf8_percent_encode(
                    filename,
                    percent_encoding::NON_ALPHANUMERIC
                ).to_string();

                let response = Response::builder()
                    .header(header::CONTENT_TYPE, "application/octet-stream")
                    .header(
                        header::CONTENT_DISPOSITION,
                        format!("attachment; filename*=UTF-8''{}", encoded_filename),
                    )
                    .header(header::CONTENT_LENGTH, metadata.len())
                    .body(body)
                    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Response build error: {}", e)))?;

                Ok(response)
            } else {
                Err((StatusCode::BAD_REQUEST, "Requested item is not a file".to_string()))
            }
        }
        None => Err((StatusCode::NOT_FOUND, "Item not found".to_string())),
    }
}

// Handler for /clipboard/:id
async fn get_clipboard(Path(id): Path<String>) -> impl IntoResponse {
    let item_opt = {
        let guard = STAGED_ITEMS.read().unwrap_or_else(|e| e.into_inner());
        guard.get(&id).cloned()
    };

    match item_opt {
        Some(item) => {
            if let (StagedItemType::Text, Some(text)) = (item.item_type, item.text) {
                let response = Response::builder()
                    .header(header::CONTENT_TYPE, "text/plain; charset=utf-8")
                    .body(Body::from(text))
                    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Response build error: {}", e)))?;
                Ok(response)
            } else {
                Err((StatusCode::BAD_REQUEST, "Requested item is not text".to_string()))
            }
        }
        None => Err((StatusCode::NOT_FOUND, "Item not found".to_string())),
    }
}

// Handler for / (Web UI)
async fn web_ui() -> impl IntoResponse {
    Html(include_str!("index.html"))
}

#[derive(Deserialize)]
struct RequestUploadPayload {
    name: String,
    size: u64,
}

#[derive(Serialize)]
struct RequestUploadResponse {
    token: Option<String>,
    error: Option<String>,
}

#[derive(Deserialize)]
struct UploadQuery {
    token: Option<String>,
}

async fn request_upload(Json(payload): Json<RequestUploadPayload>) -> impl IntoResponse {
    let id = Uuid::new_v4().to_string();
    
    let (tx, rx) = tokio::sync::oneshot::channel();
    {
        let mut pending = PENDING_UPLOADS.write().unwrap_or_else(|e| e.into_inner());
        pending.insert(id.clone(), tx);
    }
    
    let sink_opt = {
        let guard = UPLOAD_REQUEST_SINK.read().unwrap_or_else(|e| e.into_inner());
        guard.clone()
    };
    
    if let Some(sink) = sink_opt {
        let req = UploadRequest {
            id: id.clone(),
            name: payload.name,
            size: payload.size,
        };
        let _ = sink.add(req);
    } else {
        // If no UI listener is active, deny by default
        return (StatusCode::FORBIDDEN, Json(RequestUploadResponse { token: None, error: Some("No UI listener active".to_string()) }));
    }
    
    // Wait for the UI response
    let accepted = rx.await.unwrap_or(false);
    
    if accepted {
        {
            let mut approved = APPROVED_TOKENS.write().unwrap_or_else(|e| e.into_inner());
            approved.insert(id.clone());
        }
        (StatusCode::OK, Json(RequestUploadResponse { token: Some(id), error: None }))
    } else {
        (StatusCode::FORBIDDEN, Json(RequestUploadResponse { token: None, error: Some("Upload rejected by user".to_string()) }))
    }
}

// Handler for /upload
async fn upload_file(Query(query): Query<UploadQuery>, mut multipart: Multipart) -> impl IntoResponse {
    let token = match query.token {
        Some(t) => t,
        None => return (StatusCode::UNAUTHORIZED, "Missing token".to_string()),
    };
    
    let is_approved = {
        let mut approved = APPROVED_TOKENS.write().unwrap_or_else(|e| e.into_inner());
        approved.remove(&token) // Remove immediately to prevent reuse
    };
    
    if !is_approved {
        return (StatusCode::FORBIDDEN, "Invalid or expired token".to_string());
    }
    let mut uploaded_ids = Vec::new();
    while let Ok(Some(mut field)) = multipart.next_field().await {
        let raw_name = field.file_name().unwrap_or("unnamed_file").to_string();
        // Sanitize filename: strip path separators to prevent directory traversal
        let name = raw_name.replace(['/', '\\', ':', '\0'], "_");
        
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
        let _ = tokio::fs::create_dir_all(&path).await;
        let id = Uuid::new_v4().to_string();
        path.push(format!("recv_{}_{}", id, name));
        
        let mut file = match File::create(&path).await {
            Ok(f) => f,
            Err(_) => continue,
        };
        
        let mut size = 0u64;
        while let Ok(Some(chunk)) = field.chunk().await {
            size += chunk.len() as u64;
            if file.write_all(&chunk).await.is_err() {
                break;
            }
        }
        
        let item = StagedItem {
            id: id.clone(),
            name,
            item_type: StagedItemType::File,
            path: Some(path.to_string_lossy().to_string()),
            text: None,
            size,
        };
        
        {
            let mut guard = RECEIVED_ITEMS.write().unwrap_or_else(|e| e.into_inner());
            guard.insert(id.clone(), item);
        }
        uploaded_ids.push(id);
    }
    
    (StatusCode::OK, format!("Uploaded {} files", uploaded_ids.len()))
}

pub async fn run_server(port: u16, shutdown_rx: tokio::sync::oneshot::Receiver<()>) -> Result<(), axum::BoxError> {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([Method::GET, Method::POST])
        .allow_headers(Any);

    let app = Router::new()
        .route("/", get(web_ui))
        .route("/info", get(get_info))
        .route("/files/:id", get(download_file))
        .route("/clipboard/:id", get(get_clipboard))
        .route("/request_upload", post(request_upload))
        .route("/upload", post(upload_file))
        .layer(cors);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = tokio::net::TcpListener::bind(addr).await?;
    
    axum::serve(listener, app)
        .with_graceful_shutdown(async move {
            let _ = shutdown_rx.await;
        })
        .await?;

    Ok(())
}
