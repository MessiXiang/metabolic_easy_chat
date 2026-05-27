<p align="center">
  <img src="easy_chat/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="easy_chat logo" width="132" height="132">
</p>

<h1 align="center">easy_chat</h1>

<p align="center">
  A native macOS AI workspace for chat, files, terminal commands, MCP tools, and local skills.
</p>

<p align="center">
  <a href="http://buaa.spotterblog.cn/easy_chat/">Website</a>
  ·
  <a href="https://github.com/MessiXiang/easy_chat">Repository</a>
</p>

## Overview

easy_chat is a SwiftUI macOS app that brings model chat, workspace context, terminal execution, image generation, MCP servers, and reusable skills into one desktop interface. It is designed for coding and research workflows where the assistant needs to see files, run approved commands, and keep the conversation close to the project.

## Features

- Native SwiftUI interface for macOS.
- OpenAI-compatible chat with support for streaming responses.
- Responses API and Chat Completions fallback support.
- Image generation mode with configurable output size.
- Workspace file browser for adding project files to chat context.
- Built-in terminal sessions with command approval flow.
- MCP server configuration for external tools.
- Local Skills support for reusable task instructions and knowledge.
- Conversation history, message editing, regeneration, and attachments.

## Website

The promotional site is published with GitHub Pages:

<http://buaa.spotterblog.cn/easy_chat/>

The static site source lives in `docs/` and is deployed by `.github/workflows/pages.yml`.

## Requirements

- macOS
- Xcode 16 or newer recommended
- A compatible OpenAI-style API provider and API key

## Run Locally

1. Clone the repository.
2. Open `easy_chat.xcodeproj` in Xcode.
3. Select the `easy_chat` scheme.
4. Build and run the app.
5. Open settings inside the app and configure your API base URL, API key, and model names.

## Project Structure

- `easy_chat/ContentView.swift`: main SwiftUI interface.
- `easy_chat/ChatViewModel.swift`: app state, chat flow, workspace actions, and terminal coordination.
- `easy_chat/OpenAICompatibleClient.swift`: OpenAI-compatible API client.
- `easy_chat/ToolInvocationService.swift`: tool call handling.
- `easy_chat/WorkspaceTerminalService.swift`: terminal command execution support.
- `docs/`: GitHub Pages promotional site.

## Notes

This project stores provider settings locally in the app. Do not commit API keys, tokens, or private workspace data.

## License

No license has been specified yet.