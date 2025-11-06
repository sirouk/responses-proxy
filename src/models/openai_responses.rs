use serde::{Deserialize, Serialize};
use serde_json::Value;

// ---------- Request Models (OpenAI Responses API) ----------

#[derive(Deserialize, Debug)]
#[serde(untagged)]
pub enum ResponseInput {
    String(String),
    Array(Vec<ResponseInputItem>),
}

#[derive(Deserialize, Debug)]
#[serde(tag = "type")]
pub enum ResponseInputItem {
    #[serde(rename = "message")]
    Message {
        role: String,
        content: ResponseContent,
    },
    #[serde(rename = "reasoning")]
    Reasoning {
        #[serde(default)]
        text: Option<String>,
        #[serde(default)]
        encrypted_content: Option<String>,
    },
    #[serde(rename = "item_reference")]
    ItemReference { id: String },
    #[serde(rename = "function_call")]
    FunctionCall {
        call_id: String,
        name: String,
        arguments: String,
    },
    #[serde(rename = "function_call_output")]
    FunctionCallOutput { call_id: String, output: String },
}

#[derive(Deserialize, Debug)]
#[serde(untagged)]
pub enum ResponseContent {
    String(String),
    Array(Vec<ContentPart>),
}

#[derive(Deserialize, Debug)]
#[serde(tag = "type")]
pub enum ContentPart {
    #[serde(rename = "input_text")]
    InputText { text: String },
    #[serde(rename = "output_text")] // Accept output_text in input (for multi-turn)
    OutputText { text: String },
    #[serde(rename = "input_image")]
    InputImage { image_url: ImageUrl },
    #[serde(rename = "reasoning")]
    Reasoning {
        text: String,
        #[serde(default)]
        encrypted_content: Option<String>,
    },
}

#[derive(Deserialize, Debug)]
pub struct ImageUrl {
    pub url: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(untagged)]
pub enum Tool {
    /// Responses API format: {type: "function", function: {name, description, parameters}}
    Nested {
        #[serde(rename = "type")]
        type_: String,
        function: FunctionDef,
    },
    /// Chat Completions format (also accepted by Responses API): {type: "function", name, description, parameters, strict}
    /// Also catches non-function tools like web_search, custom, etc.
    Flat {
        #[serde(rename = "type")]
        type_: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        name: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        description: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        parameters: Option<Value>,
        #[serde(default)]
        strict: bool,
        #[serde(flatten)]
        extra: Value,
    },
}

impl Tool {
    pub fn type_(&self) -> &str {
        match self {
            Tool::Nested { type_, .. } => type_,
            Tool::Flat { type_, .. } => type_,
        }
    }

    pub fn function_def(&self) -> FunctionDef {
        match self {
            Tool::Nested { function, .. } => function.clone(),
            Tool::Flat {
                name,
                description,
                parameters,
                type_,
                extra,
                ..
            } => {
                // For flat tools, use provided fields or fall back to type/extra
                let func_name = name
                    .clone()
                    .or_else(|| {
                        extra
                            .get("name")
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string())
                    })
                    .unwrap_or_else(|| type_.clone());

                let func_desc = description.clone().or_else(|| {
                    extra
                        .get("description")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string())
                });

                let func_params = parameters
                    .clone()
                    .unwrap_or_else(|| Value::Object(serde_json::Map::new()));

                FunctionDef {
                    name: func_name,
                    description: func_desc,
                    parameters: func_params,
                }
            }
        }
    }
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct FunctionDef {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub parameters: Value,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(untagged)]
pub enum ToolChoice {
    String(String), // "auto", "none", "required"
    Specific(ToolChoiceSpecific),
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct ToolChoiceSpecific {
    #[serde(rename = "type")]
    pub type_: String, // "function"
    pub function: FunctionChoice,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct FunctionChoice {
    pub name: String,
}

#[derive(Deserialize, Debug)]
pub struct ResponseRequest {
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub input: Option<ResponseInput>,
    #[serde(default)]
    pub instructions: Option<String>,
    #[serde(default)]
    pub max_output_tokens: Option<u32>,
    #[serde(default)]
    pub temperature: Option<f32>,
    #[serde(default)]
    pub top_p: Option<f32>,
    #[serde(default)]
    pub tools: Option<Vec<Tool>>,
    #[serde(default)]
    pub tool_choice: Option<ToolChoice>,
    #[serde(default)]
    pub parallel_tool_calls: Option<bool>,
    #[serde(default)]
    pub stream: Option<bool>,
    #[serde(default)]
    pub metadata: Option<Value>,
    #[serde(default)]
    pub store: Option<bool>,
}

// ---------- Response Models (OpenAI Responses API) ----------

#[derive(Serialize, Debug)]
pub struct Response {
    pub id: String,
    pub object: String, // "response"
    pub created_at: u64,
    pub status: String, // "completed", "failed", "in_progress", "incomplete", "cancelled", "queued"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ResponseError>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub incomplete_details: Option<IncompleteDetails>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    pub output: Vec<OutputItem>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub usage: Option<Usage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<Value>,
    // Echo back request parameters
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instructions: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tools: Option<Vec<Tool>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_choice: Option<ToolChoice>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parallel_tool_calls: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub top_p: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_output_tokens: Option<u32>,
}

#[derive(Serialize, Debug, Clone)]
pub struct ResponseError {
    pub code: String,
    pub message: String,
}

#[derive(Serialize, Debug, Clone)]
pub struct IncompleteDetails {
    pub reason: String, // "max_output_tokens", "content_filter"
}

#[derive(Serialize, Debug, Clone)]
pub struct OutputItem {
    pub id: String,
    #[serde(rename = "object")]
    pub object: String,
    #[serde(rename = "type")]
    pub type_: String, // "message", "function_call", "function_call_output", "reasoning", "refusal"
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<Vec<OutputContent>>,
    // For function_call items
    #[serde(skip_serializing_if = "Option::is_none")]
    pub call_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub arguments: Option<String>,
    // For function_call_output items
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
}

#[derive(Serialize, Debug, Clone)]
#[serde(tag = "type")]
pub enum OutputContent {
    #[serde(rename = "output_text")]
    OutputText {
        text: String,
        #[serde(skip_serializing_if = "Vec::is_empty")]
        annotations: Vec<Value>,
    },
    #[serde(rename = "reasoning")]
    Reasoning { text: String },
}

#[derive(Serialize, Debug)]
pub struct Usage {
    pub input_tokens: u32,
    pub output_tokens: u32,
    pub total_tokens: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub input_tokens_details: Option<TokenDetails>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_tokens_details: Option<TokenDetails>,
}

#[derive(Serialize, Debug)]
pub struct TokenDetails {
    pub cached_tokens: u32,
    pub reasoning_tokens: u32,
}

// ---------- Streaming Events ----------

#[derive(Serialize, Debug)]
pub struct StreamEvent {
    #[serde(rename = "type")]
    pub type_: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub event_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub response_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub response: Option<Response>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub item_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_index: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_index: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub delta: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub item: Option<OutputItem>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sequence_number: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub call_id: Option<String>,
    // For function call events
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub arguments: Option<String>,
    // For error events
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ResponseError>,
}
