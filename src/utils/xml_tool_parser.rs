/// Parse XML-style tool calls from text and convert to structured format
/// Handles formats like:
/// <function=name>
/// <parameter=key>value</parameter>
/// </function>
use serde_json::json;

#[derive(Debug, Clone)]
pub struct ParsedToolCall {
    pub name: String,
    pub arguments: String,
}

/// Quick heuristic to detect whether text contains XML-style tool call syntax.
fn contains_xml_tool_call(text: &str) -> bool {
    let normalized = text.to_ascii_lowercase();
    normalized.contains("<function=")
        || normalized.contains("</function>")
        || normalized.contains("<tool_call")
        || normalized.contains("</tool_call>")
        || normalized.contains("<parameter=")
}

/// Extract and parse XML-style tool calls from text
/// Returns (cleaned_text, parsed_calls)
pub fn extract_xml_tool_calls(text: &str) -> (String, Vec<ParsedToolCall>) {
    if !contains_xml_tool_call(text) {
        return (text.trim().to_string(), Vec::new());
    }

    let mut calls = Vec::new();
    let mut cleaned = text.to_string();

    // Pattern: <function=name>...<parameter=key>value</parameter>...</function>
    // We'll use a simple state machine parser for safety

    let mut start_idx = 0;
    while let Some(func_start) = cleaned[start_idx..].find("<function=") {
        let absolute_start = start_idx + func_start;

        // Find function name
        let name_start = absolute_start + "<function=".len();
        let name_end = match cleaned[name_start..].find('>') {
            Some(idx) => name_start + idx,
            None => break,
        };

        let function_name = cleaned[name_start..name_end].to_string();

        // Find closing </function> or </tool_call>
        let content_start = name_end + 1;
        let end_tag = if let Some(idx) = cleaned[content_start..].find("</function>") {
            content_start + idx + "</function>".len()
        } else if let Some(idx) = cleaned[content_start..].find("</tool_call>") {
            content_start + idx + "</tool_call>".len()
        } else {
            // Incomplete tool call, skip for now
            start_idx = name_end + 1;
            continue;
        };

        let content = &cleaned[content_start..end_tag];

        // Parse parameters
        let mut params = serde_json::Map::new();
        let mut param_start = 0;

        while let Some(param_idx) = content[param_start..].find("<parameter=") {
            let abs_param_start = param_start + param_idx;
            let param_name_start = abs_param_start + "<parameter=".len();

            // Extract parameter name
            let param_name_end = match content[param_name_start..].find('>') {
                Some(idx) => param_name_start + idx,
                None => break,
            };

            let param_name = content[param_name_start..param_name_end].to_string();

            // Extract parameter value (until </parameter>)
            let param_value_start = param_name_end + 1;
            let param_value_end = match content[param_value_start..].find("</parameter>") {
                Some(idx) => param_value_start + idx,
                None => break,
            };

            let param_value = content[param_value_start..param_value_end]
                .trim()
                .to_string();
            params.insert(param_name, json!(param_value));

            param_start = param_value_end + "</parameter>".len();
        }

        // Convert params to JSON string
        let arguments = serde_json::to_string(&params).unwrap_or_else(|_| "{}".to_string());

        calls.push(ParsedToolCall { name: function_name, arguments });

        // Remove this XML from cleaned text
        cleaned = format!("{}{}", &cleaned[..absolute_start], &cleaned[end_tag..]);

        // Reset search position since we modified the string
        start_idx = absolute_start;
    }

    (cleaned.trim().to_string(), calls)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_xml_tool_call() {
        assert!(contains_xml_tool_call("<function=test>"));
        assert!(contains_xml_tool_call("Some text <parameter=key>"));
        assert!(!contains_xml_tool_call("Regular text"));
    }

    #[test]
    fn test_extract_simple_tool_call() {
        let input = r#"Let me help.
<function=apply_patch>
<parameter=patch>
*** Begin Patch
*** End Patch
</parameter>
</function>"#;

        let (cleaned, calls) = extract_xml_tool_calls(input);
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].name, "apply_patch");
        assert!(calls[0].arguments.contains("patch"));
        assert_eq!(cleaned, "Let me help.");
    }

    #[test]
    fn test_extract_multiple_params() {
        let input = r#"<function=read_file>
<parameter=file_path>
test.txt
</parameter>
<parameter=limit>
100
</parameter>
</function>"#;

        let (_, calls) = extract_xml_tool_calls(input);
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].name, "read_file");
    }
}
