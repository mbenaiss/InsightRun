//
//  MarkdownView.swift
//  InsightRun
//
//  Created by InsightRun AI on 2025-11-21.
//

import SwiftUI

struct MarkdownView: View {
    let content: String
    @State private var parsedNodes: [MarkdownNode] = []
    
    init(_ content: String) {
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parsedNodes) { node in
                MarkdownNodeView(node: node)
            }
        }
        .onAppear {
            parsedNodes = MarkdownParser.parse(content)
        }
        .onChange(of: content) { _, newValue in
            parsedNodes = MarkdownParser.parse(newValue)
        }
    }
}

// MARK: - Node Views

// MARK: - Node Views

struct MarkdownNodeView: View {
    let node: MarkdownNode
    
    var body: some View {
        switch node.type {
        case .header(let level, let text):
            Text(LocalizedStringKey(text))
                .font(headerFont(for: level))
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextPrimary)
                .padding(.top, level == 1 ? 8 : 4)
            
        case .paragraph(let text):
            Text(LocalizedStringKey(text))
                .foregroundStyle(Color.irTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            
        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(Color.irTextSecondary)
                        Text(LocalizedStringKey(item))
                            .foregroundStyle(Color.irTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 8)
            
        case .table(let headers, let rows):
            MarkdownTableView(headers: headers, rows: rows)
            
        case .codeBlock(let code):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color.irCardBackground.opacity(0.5))
                .cornerRadius(8)
        }
    }
    
    private func headerFont(for level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .headline
        case 3: return .subheadline
        default: return .body
        }
    }
}

struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Headers
                if !headers.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(0..<headers.count, id: \.self) { index in
                            Text(LocalizedStringKey(headers[index]))
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.irTextSecondary)
                                .textCase(.uppercase)
                                .frame(minWidth: 100, alignment: .leading)
                                .padding(12)
                                .background(Color.irCardBackground)
                        }
                    }
                    
                    Divider()
                }
                
                // Rows
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    let row = rows[rowIndex]
                    HStack(spacing: 0) {
                        ForEach(0..<max(headers.count, row.count), id: \.self) { colIndex in
                            if colIndex < row.count {
                                Text(LocalizedStringKey(row[colIndex]))
                                    .font(.callout)
                                    .foregroundStyle(Color.irTextPrimary)
                                    .frame(minWidth: 100, alignment: .leading)
                                    .padding(12)
                            } else {
                                Spacer()
                                    .frame(minWidth: 100)
                            }
                        }
                    }
                    .background(rowIndex % 2 == 0 ? Color.clear : Color.irCardBackground.opacity(0.3))
                    
                    if rowIndex < rows.count - 1 {
                        Divider()
                            .opacity(0.5)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.irPrimaryAccent.opacity(0.1), lineWidth: 1)
                    .background(Color.irCardBackground.opacity(0.1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Parser Models

struct MarkdownNode: Identifiable {
    let id = UUID()
    let type: MarkdownNodeType
}

enum MarkdownNodeType {
    case header(level: Int, text: String)
    case paragraph(text: String)
    case list(items: [String])
    case table(headers: [String], rows: [[String]])
    case codeBlock(code: String)
}

// MARK: - Parser Logic

struct MarkdownParser {
    static func parse(_ text: String) -> [MarkdownNode] {
        var nodes: [MarkdownNode] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            if line.isEmpty {
                i += 1
                continue
            }
            
            // Headers
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                nodes.append(MarkdownNode(type: .header(level: level, text: text)))
                i += 1
            }
            // Lists
            else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count {
                    let currentLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if currentLine.hasPrefix("- ") || currentLine.hasPrefix("* ") {
                        items.append(String(currentLine.dropFirst(2)))
                        i += 1
                    } else {
                        break
                    }
                }
                nodes.append(MarkdownNode(type: .list(items: items)))
            }
            // Tables
            else if line.contains("|") && i + 1 < lines.count && lines[i+1].contains("|") && lines[i+1].contains("-") {
                // Parse Table
                let headerLine = line
                let separatorLine = lines[i+1]
                
                // Check if it's a valid table start
                if isTableSeparator(separatorLine) {
                    let headers = parseTableLine(headerLine)
                    var rows: [[String]] = []
                    
                    i += 2 // Skip header and separator
                    
                    while i < lines.count {
                        let currentLine = lines[i].trimmingCharacters(in: .whitespaces)
                        if currentLine.contains("|") {
                            rows.append(parseTableLine(currentLine))
                            i += 1
                        } else {
                            break
                        }
                    }
                    nodes.append(MarkdownNode(type: .table(headers: headers, rows: rows)))
                } else {
                    // Not a table, treat as paragraph
                    nodes.append(MarkdownNode(type: .paragraph(text: line)))
                    i += 1
                }
            }
            // Code Blocks
            else if line.hasPrefix("```") {
                var code = ""
                i += 1 // Skip opening fence
                while i < lines.count {
                    let currentLine = lines[i]
                    if currentLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    code += currentLine + "\n"
                    i += 1
                }
                nodes.append(MarkdownNode(type: .codeBlock(code: code)))
            }
            // Paragraphs
            else {
                nodes.append(MarkdownNode(type: .paragraph(text: line)))
                i += 1
            }
        }
        
        return nodes
    }
    
    static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Must contain | and - and no other alphanumeric chars (roughly)
        return trimmed.contains("|") && trimmed.contains("-") && !trimmed.contains(where: { $0.isLetter || $0.isNumber })
    }
    
    static func parseTableLine(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Remove leading/trailing pipes if they exist
        let content = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
