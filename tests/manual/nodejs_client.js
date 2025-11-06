#!/usr/bin/env node
/**
 * Manual Node.js client for the OpenAI Responses Proxy.
 *
 * Requires:
 *   PROXY_URL (default: http://localhost:8282)
 *   CHUTES_API_KEY (default: cpk_test)
 *
 * Usage:
 *   node tests/manual/nodejs_client.js
 */

const https = require('https');
const http = require('http');

const PROXY_URL = process.env.PROXY_URL || 'http://localhost:8282';
const API_KEY = process.env.CHUTES_API_KEY || 'cpk_test';

function createRequestOptions(url) {
  return {
    hostname: url.hostname,
    port: url.port || (url.protocol === 'https:' ? 443 : 80),
    path: url.pathname,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${API_KEY}`,
    },
  };
}

function streamRequest(postData) {
  const url = new URL(`${PROXY_URL}/v1/responses`);
  const protocol = url.protocol === 'https:' ? https : http;
  const options = createRequestOptions(url);

  return new Promise((resolve, reject) => {
    const req = protocol.request(options, (res) => {
      let buffer = '';

      res.on('data', (chunk) => {
        buffer += chunk.toString();
        const lines = buffer.split('\n');

        for (let i = 0; i < lines.length - 1; i += 1) {
          const line = lines[i].trim();
          if (!line.startsWith('data: ')) continue;

          const data = line.substring(6);
          if (data === '[DONE]') {
            continue;
          }

          try {
            const event = JSON.parse(data);
            if (event.type === 'response.output_text.delta') {
              process.stdout.write(event.delta || '');
            } else if (event.type === 'response.completed') {
              process.stdout.write('\n\nstatus: ' + event.response?.status + '\n');
            }
          } catch (err) {
            process.stdout.write(`\n(raw) ${data}\n`);
          }
        }

        buffer = lines[lines.length - 1];
      });

      res.on('end', resolve);
    });

    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

async function simpleRequest() {
  console.log('=== Simple Request ===\n');
  const payload = JSON.stringify({
    model: 'gpt-4o',
    input: 'Tell me a short joke',
    stream: true,
    max_output_tokens: 100,
  });
  await streamRequest(payload);
  console.log('\n');
}

async function multiTurnConversation() {
  console.log('=== Multi-turn Conversation ===\n');
  const payload = JSON.stringify({
    model: 'gpt-4o',
    instructions: 'You are a helpful assistant.',
    input: [
      { type: 'message', role: 'user', content: 'What is the capital of France?' },
      { type: 'message', role: 'assistant', content: 'The capital of France is Paris.' },
      { type: 'message', role: 'user', content: 'What is its population?' },
    ],
    stream: true,
    max_output_tokens: 200,
  });
  await streamRequest(payload);
  console.log('\n');
}

(async () => {
  try {
    await simpleRequest();
    await multiTurnConversation();
  } catch (err) {
    console.error('Request error:', err.message);
    process.exitCode = 1;
  }
})();

