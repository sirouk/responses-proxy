use crate::models::App;
use axum::{extract::State, http::StatusCode, Json};
use serde_json::{json, Value};

pub async fn health_check(State(app): State<App>) -> (StatusCode, Json<Value>) {
    let cb = app.circuit_breaker.read().await;

    let status = if cb.enabled && cb.is_open {
        StatusCode::SERVICE_UNAVAILABLE
    } else {
        StatusCode::OK
    };

    let response = json!({
        "status": if status == StatusCode::OK { "healthy" } else { "unhealthy" },
        "circuit_breaker": {
            "enabled": cb.enabled,
            "is_open": cb.is_open,
            "consecutive_failures": cb.consecutive_failures
        }
    });

    (status, Json(response))
}
