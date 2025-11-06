use crate::models::ModelInfo;

/// Format a backend error into a user-friendly message
pub fn format_backend_error(error_msg: &str, _raw_body: &str) -> String {
    format!(
        "⚠️ Backend Error:\n\n{}\n\nPlease check your request parameters and try again.",
        error_msg
    )
}

/// Build a formatted model list for 404 responses
pub fn build_model_list_content(requested_model: &str, models: &[ModelInfo]) -> String {
    let mut content = format!("❌ Model '{}' not found.\n\n", requested_model);

    if !models.is_empty() {
        content.push_str("Available models:\n\n");
        for model in models.iter().take(20) {
            let price_suffix = match (model.input_price_usd, model.output_price_usd) {
                (Some(input), Some(output)) => {
                    format!(" (input ${:.4}/1K, output ${:.4}/1K)", input, output)
                }
                (Some(input), None) => format!(" (input ${:.4}/1K)", input),
                (None, Some(output)) => format!(" (output ${:.4}/1K)", output),
                (None, None) => String::new(),
            };
            content.push_str(&format!("  • {}{}\n", model.id, price_suffix));
        }

        if models.len() > 20 {
            content.push_str(&format!("\n...and {} more models.\n", models.len() - 20));
        }
    } else {
        content.push_str("No models available from backend.\n");
    }

    content
}
