use chrono::Utc;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::sync::OnceLock;

static LOG_VOLUME_ENABLED: OnceLock<bool> = OnceLock::new();

fn log_volume_enabled() -> bool {
    *LOG_VOLUME_ENABLED.get_or_init(|| {
        env::var("ENABLE_LOG_VOLUME")
            .ok()
            .map(|value| {
                let normalized = value.trim().to_ascii_lowercase();
                matches!(normalized.as_str(), "1" | "true" | "yes" | "on")
            })
            .unwrap_or(false)
    })
}

fn log_dir() -> PathBuf {
    env::var("LOG_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("logs"))
}

/// Dump request body to file
pub fn dump_request(body: &str, request_id: &str) {
    if !log_volume_enabled() {
        return;
    }
    if let Err(e) = try_dump_request(body, request_id) {
        log::warn!("Failed to dump request {}: {}", request_id, e);
    }
}

fn try_dump_request(body: &str, request_id: &str) -> std::io::Result<()> {
    let timestamp = Utc::now().format("%Y%m%d_%H%M%S%.3f");
    let filename = format!("{}_request_{}.json", timestamp, request_id);
    let path = log_dir().join(filename);

    // Pretty print if possible
    let formatted = match serde_json::from_str::<serde_json::Value>(body) {
        Ok(json) => serde_json::to_string_pretty(&json).unwrap_or_else(|_| body.to_string()),
        Err(_) => body.to_string(),
    };

    fs::write(&path, formatted)?;
    log::debug!("📝 Dumped request to: {}", path.display());
    Ok(())
}

/// Dump streaming events to file
pub fn dump_stream_event(event: &str, request_id: &str, sequence: u32) {
    if !log_volume_enabled() {
        return;
    }
    if let Err(e) = try_dump_stream_event(event, request_id, sequence) {
        log::warn!(
            "Failed to dump stream event {} for {}: {}",
            sequence,
            request_id,
            e
        );
    }
}

fn try_dump_stream_event(event: &str, request_id: &str, sequence: u32) -> std::io::Result<()> {
    let timestamp = Utc::now().format("%Y%m%d_%H%M%S%.3f");
    let filename = format!("{}_stream_{}_{:04}.json", timestamp, request_id, sequence);
    let path = log_dir().join(filename);

    // Pretty print if possible
    let formatted = match serde_json::from_str::<serde_json::Value>(event) {
        Ok(json) => serde_json::to_string_pretty(&json).unwrap_or_else(|_| event.to_string()),
        Err(_) => event.to_string(),
    };

    fs::write(&path, formatted)?;
    log::trace!("📝 Dumped stream event {} to: {}", sequence, path.display());
    Ok(())
}

/// Dump backend request being sent
pub fn dump_backend_request(body: &str, request_id: &str) {
    if !log_volume_enabled() {
        return;
    }
    if let Err(e) = try_dump_backend_request(body, request_id) {
        log::warn!("Failed to dump backend request {}: {}", request_id, e);
    }
}

fn try_dump_backend_request(body: &str, request_id: &str) -> std::io::Result<()> {
    let timestamp = Utc::now().format("%Y%m%d_%H%M%S%.3f");
    let filename = format!("{}_backend_request_{}.json", timestamp, request_id);
    let path = log_dir().join(filename);

    // Pretty print if possible
    let formatted = match serde_json::from_str::<serde_json::Value>(body) {
        Ok(json) => serde_json::to_string_pretty(&json).unwrap_or_else(|_| body.to_string()),
        Err(_) => body.to_string(),
    };

    fs::write(&path, formatted)?;
    log::debug!("📝 Dumped backend request to: {}", path.display());
    Ok(())
}

/// Dump backend streaming chunk
pub fn dump_backend_chunk(chunk: &str, request_id: &str, chunk_num: u32) {
    if !log_volume_enabled() {
        return;
    }
    if let Err(e) = try_dump_backend_chunk(chunk, request_id, chunk_num) {
        log::warn!(
            "Failed to dump backend chunk {} for {}: {}",
            chunk_num,
            request_id,
            e
        );
    }
}

fn try_dump_backend_chunk(chunk: &str, request_id: &str, chunk_num: u32) -> std::io::Result<()> {
    let timestamp = Utc::now().format("%Y%m%d_%H%M%S%.3f");
    let filename = format!(
        "{}_backend_chunk_{}_{:04}.txt",
        timestamp, request_id, chunk_num
    );
    let path = log_dir().join(filename);

    fs::write(&path, chunk)?;
    log::trace!(
        "📝 Dumped backend chunk {} to: {}",
        chunk_num,
        path.display()
    );
    Ok(())
}

/// Initialize logging directory
pub fn init_log_dir() -> std::io::Result<()> {
    if !log_volume_enabled() {
        return Ok(());
    }
    let dir = log_dir();
    fs::create_dir_all(&dir)?;
    log::info!("📁 Logging directory initialized: {}", dir.display());
    Ok(())
}
