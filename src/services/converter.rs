use crate::models::{
    ChatCompletionRequest, ChatFunction, ChatMessage, ChatTool, ContentPart, ResponseContent,
    ResponseInput, ResponseInputItem, ResponseRequest,
};
use serde_json::{json, Value};

/// Convert OpenAI Responses API request to Chat Completions format
pub fn convert_to_chat_completions(req: &ResponseRequest) -> Result<ChatCompletionRequest, String> {
    let model = req.model.as_ref().ok_or("Model is required")?.clone();

    let mut messages = Vec::new();

    // Add instructions as system message if provided
    if let Some(instructions) = &req.instructions {
        if !instructions.is_empty() {
            // Append tool calling format override for Chat Completions compatibility
            let tool_override = "\n\n---\n\nIMPORTANT: Tool Calling Format Override\nWhen calling functions/tools, you MUST use the standard OpenAI Chat Completions JSON format, NOT any XML or custom syntax. The system will automatically handle tool execution. Never output tool calls as text - use the native function calling mechanism.";
            let enhanced_instructions = format!("{}{}", instructions, tool_override);

            messages.push(ChatMessage {
                role: "system".to_string(),
                content: Some(json!(enhanced_instructions)),
                tool_calls: None,
                tool_call_id: None,
            });
        }
    }

    // Convert input to messages
    if let Some(input) = &req.input {
        match input {
            ResponseInput::String(text) => {
                messages.push(ChatMessage {
                    role: "user".to_string(),
                    content: Some(json!(text)),
                    tool_calls: None,
                    tool_call_id: None,
                });
            }
            ResponseInput::Array(items) => {
                let mut accumulated_reasoning: Vec<String> = Vec::new();
                let mut pending_tool_calls: Vec<Value> = Vec::new();

                for item in items {
                    match item {
                        ResponseInputItem::Message { role, content } => {
                            let (mut msg_content, content_reasoning) =
                                convert_response_content(content);

                            // If content has inline reasoning, accumulate it
                            if let Some(content_think) = content_reasoning {
                                accumulated_reasoning.push(content_think);
                            }

                            // If assistant message and we have accumulated reasoning, prepend as <think> tags
                            if role == "assistant" && !accumulated_reasoning.is_empty() {
                                let thinking_text = accumulated_reasoning.join("\n");
                                let original_content = msg_content.as_str().unwrap_or("");
                                let combined = format!(
                                    "<think>{}</think>\n{}",
                                    thinking_text, original_content
                                );
                                msg_content = json!(combined);
                                log::info!("🧠 INPUT: Prepended {} reasoning part(s) ({} chars) to assistant message as <think> tags", 
                                    accumulated_reasoning.len(), thinking_text.len());
                                accumulated_reasoning.clear();
                            }

                            // If assistant message and we have pending tool calls, add them to the message
                            if role == "assistant" && !pending_tool_calls.is_empty() {
                                log::info!(
                                    "🔧 Added {} tool call(s) to assistant message",
                                    pending_tool_calls.len()
                                );
                                messages.push(ChatMessage {
                                    role: role.clone(),
                                    content: Some(msg_content),
                                    tool_calls: Some(pending_tool_calls.clone()),
                                    tool_call_id: None,
                                });
                                pending_tool_calls.clear();
                            } else {
                                messages.push(ChatMessage {
                                    role: role.clone(),
                                    content: Some(msg_content),
                                    tool_calls: None,
                                    tool_call_id: None,
                                });
                            }
                        }
                        ResponseInputItem::FunctionCall {
                            call_id,
                            name,
                            arguments,
                        } => {
                            // Accumulate tool calls to attach to the next assistant message
                            pending_tool_calls.push(json!({
                                "id": call_id,
                                "type": "function",
                                "function": {
                                    "name": name,
                                    "arguments": arguments,
                                }
                            }));
                            log::info!("🔧 INPUT: Found function_call ({}) - will attach to assistant message", name);
                        }
                        ResponseInputItem::FunctionCallOutput { call_id, output } => {
                            // The output field is a string that may contain nested JSON from Codex
                            // (e.g., {"output":"...", "metadata":{...}}). Try to extract the actual
                            // output content, otherwise use the raw string.
                            let content_str = if let Ok(parsed) =
                                serde_json::from_str::<serde_json::Value>(output)
                            {
                                if let Some(inner_output) =
                                    parsed.get("output").and_then(|v| v.as_str())
                                {
                                    inner_output.to_string()
                                } else {
                                    // Fallback to the full JSON string
                                    output.clone()
                                }
                            } else {
                                // Already a plain string
                                output.clone()
                            };

                            messages.push(ChatMessage {
                                role: "tool".to_string(),
                                content: Some(json!(content_str)),
                                tool_calls: None,
                                tool_call_id: Some(call_id.clone()),
                            });
                            log::info!(
                                "🔧 INPUT: Added function_call_output (call_id: {}, {} bytes)",
                                call_id,
                                content_str.len()
                            );
                        }
                        ResponseInputItem::Reasoning {
                            text,
                            encrypted_content,
                        } => {
                            // Accumulate reasoning to prepend to next assistant message
                            if let Some(reasoning_text) = text {
                                accumulated_reasoning.push(reasoning_text.clone());
                                log::info!("🧠 INPUT: Found reasoning item ({} chars), will prepend to next assistant message", reasoning_text.len());
                            } else if encrypted_content.is_some() {
                                log::warn!("⚠️  Encrypted reasoning content not supported (stateless mode), skipping");
                            }
                        }
                        ResponseInputItem::ItemReference { id } => {
                            log::warn!("⚠️  Item references (id: {}) are not supported in stateless mode, skipping", id);
                        }
                    }
                }

                // If reasoning items remain without an assistant message, log warning
                if !accumulated_reasoning.is_empty() {
                    log::warn!("⚠️  {} reasoning item(s) found but no following assistant message to attach to", accumulated_reasoning.len());
                }

                // If tool calls remain, we need to create an assistant message for them
                if !pending_tool_calls.is_empty() {
                    log::warn!("⚠️  {} tool call(s) found but no assistant message to attach to - tool calls may not work correctly", pending_tool_calls.len());
                }
            }
        }
    }

    // Convert tools if provided - ONLY function tools are supported
    // Simply forward tools from the client; no injection needed
    let tools = if let Some(tools_vec) = req.tools.as_ref() {
        // Filter to only function tools; others are not supported in Chat Completions API
        let non_function_tools: Vec<_> = tools_vec
            .iter()
            .filter(|t| t.type_() != "function")
            .map(|t| t.type_())
            .collect();

        if !non_function_tools.is_empty() {
            log::debug!(
                "⚠️ Skipping non-function tools (not supported by Chat Completions API): {}",
                non_function_tools.join(", ")
            );
        }

        tools_vec
            .iter()
            .filter_map(|t| {
                if t.type_() == "function" {
                    let f = t.function_def();
                    Some(ChatTool::Function {
                        type_: "function".to_string(),
                        function: ChatFunction {
                            name: f.name.clone(),
                            description: f.description.clone(),
                            parameters: f.parameters.clone(),
                        },
                    })
                } else {
                    None
                }
            })
            .collect::<Vec<_>>()
    } else {
        Vec::new()
    };

    // Tool injection has been removed. Codex CLI now properly sends all tools
    // (read_file, list_dir, grep_files, etc.) when experimental_supported_tools
    // is configured in the model family. The proxy simply forwards whatever
    // tools the client provides.

    let tools = if tools.is_empty() { None } else { Some(tools) };

    // Convert tool_choice to Value for backend
    let tool_choice = req.tool_choice.as_ref().map(|tc| {
        use crate::models::ToolChoice;
        match tc {
            ToolChoice::String(s) => json!(s),
            ToolChoice::Specific(spec) => json!(spec),
        }
    });

    Ok(ChatCompletionRequest {
        model,
        messages,
        max_tokens: req.max_output_tokens,
        temperature: req.temperature,
        top_p: req.top_p,
        tools,
        tool_choice,
        parallel_tool_calls: req.parallel_tool_calls,
        stream: req.stream.unwrap_or(false),
    })
}

/// Convert ResponseContent to JSON value for Chat Completions
/// Returns (content_value, extracted_reasoning_text)
fn convert_response_content(content: &ResponseContent) -> (Value, Option<String>) {
    match content {
        ResponseContent::String(text) => (json!(text), None),
        ResponseContent::Array(parts) => {
            let mut reasoning_text = String::new();
            let mut converted: Vec<Value> = Vec::new();

            for part in parts {
                match part {
                    ContentPart::InputText { text } | ContentPart::OutputText { text } => {
                        converted.push(json!({
                            "type": "text",
                            "text": text
                        }));
                    }
                    ContentPart::InputImage { image_url } => {
                        converted.push(json!({
                            "type": "image_url",
                            "image_url": {
                                "url": image_url.url
                            }
                        }));
                    }
                    ContentPart::Reasoning { text, .. } => {
                        // Reasoning within message content - accumulate for <think> tags
                        if !reasoning_text.is_empty() {
                            reasoning_text.push('\n');
                        }
                        reasoning_text.push_str(text);
                        log::info!(
                            "🧠 INPUT: Found reasoning in message content ({} chars)",
                            text.len()
                        );
                    }
                }
            }

            // If all text parts (no images), concatenate into string
            let has_images = parts
                .iter()
                .any(|p| matches!(p, ContentPart::InputImage { .. }));
            let has_reasoning = !reasoning_text.is_empty();

            if !has_images && !converted.is_empty() {
                let text: String = parts
                    .iter()
                    .filter_map(|p| match p {
                        ContentPart::InputText { text } | ContentPart::OutputText { text } => {
                            Some(text.as_str())
                        }
                        _ => None,
                    })
                    .collect::<Vec<_>>()
                    .join("\n");
                (
                    json!(text),
                    if has_reasoning {
                        Some(reasoning_text)
                    } else {
                        None
                    },
                )
            } else {
                (
                    json!(converted),
                    if has_reasoning {
                        Some(reasoning_text)
                    } else {
                        None
                    },
                )
            }
        }
    }
}

/// Translate Chat Completions finish_reason to Responses API status
pub fn translate_finish_reason(finish_reason: Option<&str>) -> &'static str {
    match finish_reason {
        Some("stop") => "completed",
        Some("length") => "incomplete",
        Some("content_filter") => "failed",
        Some("tool_calls") => "completed",
        Some(_) => "completed",
        None => "in_progress",
    }
}
