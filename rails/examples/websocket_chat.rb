#!/usr/bin/env ruby
# frozen_string_literal: true

##
# WebSocket Chat Example
#
# This example demonstrates how to use RAAF Rails WebSocket support
# for real-time agent conversations.
#

require_relative "../lib/raaf-rails"

# Example HTML client
HTML_CLIENT = <<~HTML.freeze
  <!DOCTYPE html>
  <html>
  <head>
    <title>RAAF WebSocket Chat</title>
    <style>
      body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
      #messages { height: 400px; overflow-y: scroll; border: 1px solid #ccc; padding: 10px; margin: 20px 0; }
      .message { margin: 10px 0; padding: 10px; border-radius: 5px; }
      .user { background: #e3f2fd; text-align: right; }
      .assistant { background: #f5f5f5; }
      .system { background: #fff3cd; text-align: center; font-style: italic; }
      #input-area { display: flex; gap: 10px; }
      #message-input { flex: 1; padding: 10px; }
      button { padding: 10px 20px; background: #2196F3; color: white; border: none; border-radius: 5px; cursor: pointer; }
      button:disabled { background: #ccc; }
    </style>
  </head>
  <body>
    <h1>RAAF WebSocket Chat Example</h1>
  #{'  '}
    <div id="status">Disconnected</div>
  #{'  '}
    <div id="messages"></div>
  #{'  '}
    <div id="input-area">
      <input type="text" id="message-input" placeholder="Type your message..." disabled>
      <button id="send-button" disabled>Send</button>
    </div>
  #{'  '}
    <script>
      // Configuration
      const WEBSOCKET_URL = 'ws://localhost:3000/chat';
      const AGENT_ID = 'demo_agent';
  #{'    '}
      // Elements
      const statusEl = document.getElementById('status');
      const messagesEl = document.getElementById('messages');
      const inputEl = document.getElementById('message-input');
      const sendButton = document.getElementById('send-button');
  #{'    '}
      // WebSocket connection
      let ws = null;
  #{'    '}
      // Add message to chat
      function addMessage(content, type = 'system') {
        const messageEl = document.createElement('div');
        messageEl.className = `message ${type}`;
        messageEl.textContent = content;
        messagesEl.appendChild(messageEl);
        messagesEl.scrollTop = messagesEl.scrollHeight;
      }
  #{'    '}
      // Connect to WebSocket
      function connect() {
        ws = new WebSocket(WEBSOCKET_URL);
  #{'      '}
        ws.onopen = () => {
          statusEl.textContent = 'Connected';
          statusEl.style.color = 'green';
          inputEl.disabled = false;
          sendButton.disabled = false;
          addMessage('Connected to chat server');
  #{'        '}
          // Join agent session
          ws.send(JSON.stringify({
            type: 'join_agent',
            agent_id: AGENT_ID
          }));
        };
  #{'      '}
        ws.onmessage = (event) => {
          const data = JSON.parse(event.data);
  #{'        '}
          switch(data.type) {
            case 'joined_agent':
              addMessage(`Joined agent: ${data.agent_name}`);
              break;
  #{'            '}
            case 'message':
              addMessage(data.content, data.role);
              break;
  #{'            '}
            case 'typing':
              statusEl.textContent = data.typing ? 'Agent is typing...' : 'Connected';
              break;
  #{'            '}
            case 'error':
              addMessage(`Error: ${data.message}`, 'system');
              break;
  #{'            '}
            default:
              console.log('Unknown message type:', data);
          }
        };
  #{'      '}
        ws.onclose = () => {
          statusEl.textContent = 'Disconnected';
          statusEl.style.color = 'red';
          inputEl.disabled = true;
          sendButton.disabled = true;
          addMessage('Disconnected from chat server');
  #{'        '}
          // Reconnect after 3 seconds
          setTimeout(connect, 3000);
        };
  #{'      '}
        ws.onerror = (error) => {
          console.error('WebSocket error:', error);
          addMessage('Connection error', 'system');
        };
      }
  #{'    '}
      // Send message
      function sendMessage() {
        const message = inputEl.value.trim();
        if (!message || !ws || ws.readyState !== WebSocket.OPEN) return;
  #{'      '}
        // Add user message to chat
        addMessage(message, 'user');
  #{'      '}
        // Send to server
        ws.send(JSON.stringify({
          type: 'chat',
          agent_id: AGENT_ID,
          content: message
        }));
  #{'      '}
        // Clear input
        inputEl.value = '';
      }
  #{'    '}
      // Event listeners
      sendButton.addEventListener('click', sendMessage);
      inputEl.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') sendMessage();
      });
  #{'    '}
      // Connect on load
      connect();
    </script>
  </body>
  </html>
HTML

# Example WebSocket server using RAAF
if __FILE__ == $PROGRAM_NAME
  require "rack"
  require "thin"

  # Create demo agent
  RAAF::Agent.new(
    name: "Demo Assistant",
    instructions: "You are a helpful assistant in a WebSocket chat demo.",
    model: "gpt-4o"
  )

  # Rack application
  app = Rack::Builder.new do
    map "/" do
      run lambda { |_env|
        [200, { "Content-Type" => "text/html" }, [HTML_CLIENT]]
      }
    end

    map "/chat" do
      run RAAF::Rails::WebsocketHandler
    end
  end

  puts "=" * 60
  puts "RAAF WebSocket Chat Example"
  puts "=" * 60
  puts
  puts "Starting server on http://localhost:3000"
  puts "Open your browser to see the chat interface"
  puts
  puts "Features demonstrated:"
  puts "- WebSocket connection management"
  puts "- Real-time message streaming"
  puts "- Typing indicators"
  puts "- Error handling"
  puts "- Auto-reconnection"
  puts
  puts "Press Ctrl+C to stop the server"
  puts "=" * 60

  Rack::Handler::Thin.run app, Port: 3000
end
