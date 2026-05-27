//
//  easy_chatTests.swift
//  easy_chatTests
//
//  Created by 向滢澔 on 2026/5/19.
//

import Testing
@testable import easy_chat

struct easy_chatTests {

    @Test func markdownParserKeepsIncompleteCodeFenceAsCode() async throws {
        let blocks = MarkdownBlock.parse("```swift\nlet value = 1")

        guard case let .code(language, code, isComplete) = blocks.first?.kind else {
            Issue.record("Expected an incomplete fenced block to render as code")
            return
        }
        #expect(language == "swift")
        #expect(code == "let value = 1")
        #expect(isComplete == false)
    }

    @Test func markdownParserExtractsCodeFenceLanguage() async throws {
        let blocks = MarkdownBlock.parse("```Mermaid title\ngraph TD\n```")

        guard case let .code(language, code, isComplete) = blocks.first?.kind else {
            Issue.record("Expected fenced code block")
            return
        }
        #expect(language == "Mermaid")
        #expect(code == "graph TD")
        #expect(isComplete)
    }

    @Test func markdownPlainTextFastPathDetectsMarkup() async throws {
        #expect(MarkdownInlineRenderer.isPlainText("hello world"))
        #expect(!MarkdownInlineRenderer.isPlainText("**hello**"))
        #expect(!MarkdownInlineRenderer.isPlainText("# Heading"))
    }

    @Test func markdownParserPreservesNestedOrderedListMarkers() async throws {
        let blocks = MarkdownBlock.parse("1. one\n2. two\n   1. child one\n   2. child two\n3. three")

        guard case let .list(items, ordered) = blocks.first?.kind else {
            Issue.record("Expected ordered list")
            return
        }
        #expect(ordered)
        #expect(items.map(\.marker) == ["1.", "2.", "3."])
        #expect(items[1].children.first?.ordered == true)
        #expect(items[1].children.first?.items.map(\.marker) == ["1.", "2."])
    }

    @Test func codeHighlighterReturnsOriginalCharacters() async throws {
        let source = "let value = \"hello\""
        let highlighted = CodeHighlighter.highlight(source, language: "swift")

        #expect(String(highlighted.characters) == source)
    }

    @Test func streamingBufferWaitsForParagraphBoundary() async throws {
        let prefix = "First paragraph\n\n"
        let tail = String(repeating: "word ", count: 260)

        #expect(MarkdownStreamingBuffer.renderablePrefix(prefix + tail) == prefix)
    }

}
