# Contributing Guide

## Development Setup

1. **Install Rust:**
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **Clone and setup:**
   ```bash
   git clone <repo>
   cd responses-proxy
   cp .env.example .env
   ```

3. **Build and run:**
   ```bash
   cargo build
   cargo run
   ```

## Code Structure

```
src/
├── models/              # Data structures
│   ├── app.rs           # App state, circuit breaker
│   ├── openai_responses.rs   # Responses API models
│   └── chat_completions.rs   # Chat Completions models
├── handlers/            # Request handlers
│   ├── responses.rs     # Main endpoint logic
│   └── health.rs        # Health check
├── services/            # Business logic
│   ├── auth.rs          # Authentication
│   ├── streaming.rs     # SSE parsing
│   ├── model_cache.rs   # Model management
│   ├── converter.rs     # Format conversion
│   └── error_formatting.rs  # Error messages
└── main.rs              # Application entry point
```

## Coding Standards

1. **Error Handling**
   - Use `Result<T, E>` for fallible operations
   - Log errors with context
   - Provide user-friendly error messages

2. **Logging**
   - Use structured logging: `log::info!(target: "metrics", "...")`
   - Include emoji for visual clarity: 🔑🚀✅❌
   - Mask sensitive data in logs

3. **Thread Safety**
   - Use `Arc<RwLock<T>>` for shared state
   - Prefer read locks over write locks
   - Keep critical sections small

4. **Performance**
   - Avoid blocking operations in async context
   - Use bounded channels for backpressure
   - Implement proper timeouts

5. **Testing**
   - Add integration tests for new features
   - Test error cases
   - Validate streaming behavior

## Adding Features

### New Request Parameter

1. Add to `ResponseRequest` in `models/openai_responses.rs`
2. Handle in `convert_to_chat_completions()` in `services/converter.rs`
3. Update documentation
4. Add test case

### New Response Event

1. Add to `StreamEvent` in `models/openai_responses.rs`
2. Emit in streaming handler in `handlers/responses.rs`
3. Update API reference
4. Add example

### New Endpoint

1. Create handler in `handlers/`
2. Add route in `main.rs`
3. Update README
4. Add tests

## Testing

**Run test suite:**
```bash
./test_proxy.sh
```

**Manual testing:**
```bash
# Terminal 1: Run proxy
RUST_LOG=debug cargo run

# Terminal 2: Send request
curl -N http://localhost:8282/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer cpk_test" \
  -d '{"model":"gpt-4o","input":"test","stream":true}'
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Run `cargo fmt` and `cargo clippy`
5. Update documentation
6. Submit PR with description

## Code Review Checklist

- [ ] Code compiles without warnings
- [ ] Tests pass
- [ ] Documentation updated
- [ ] Error handling complete
- [ ] Logging appropriate
- [ ] Performance acceptable
- [ ] Security reviewed

