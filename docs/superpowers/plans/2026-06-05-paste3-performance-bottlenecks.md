# Paste3 剩余性能瓶颈优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 继续优化 Paste3 在大文本、大图片/二进制 payload、大历史记录和自动过期清理场景下的响应时间，重点降低 MainActor 阻塞和历史查询扫描成本。

**Architecture:** 采用渐进式优化：先建立可测量基线，再把重 CPU/IO 任务移出 MainActor，随后减少图片预览重复解码，最后为大历史搜索引入独立搜索索引。每阶段都保持可单独测试、可单独回退。

**Tech Stack:** Swift 5、SwiftUI、SwiftData、AppKit、CryptoKit、OSLog、XCTest/Swift Testing、SQLite3 FTS5（第四阶段）。

---

## 路线比较

推荐路线是“测量优先 + 分阶段落地”。第一阶段只加低风险测量和批量清理优化；第二阶段改捕获链路，把大 payload hash、候选构建和文件写入移出 MainActor；第三阶段处理图片预览缓存；第四阶段再做搜索索引。优点是每一步都有明确收益和测试边界，缺点是完成全部收益需要多轮提交。

备选路线 A 是直接重写捕获和搜索两条主链路。收益最快，但会同时触碰剪贴板读取、SwiftData 写入、UI 查询和搜索语义，回归面太大。

备选路线 B 是只加 SwiftData 索引和少量缓存。实现最小，但不能解决大 payload hash/写盘阻塞，也不能从根上解决 `searchText.contains` 对大历史的线性扫描。

本计划采用推荐路线。

## 文件结构

- 修改：`paste3/ClipboardClassifier.swift`
  - 让候选构建支持异步重 CPU 路径，并避免 hash 时构造超大中间字符串。
- 修改：`paste3/ClipboardMonitor.swift`
  - 从同步 poll/insert 改为“主线程读取 pasteboard 快照，后台构建 candidate，主线程写 SwiftData”。
- 修改：`paste3/ClipboardPayloadStore.swift`
  - 移除不必要的 MainActor 约束，使文件 IO 能在后台任务中执行。
- 修改：`paste3/ClipboardStore.swift`
  - 增加批量 prune、搜索索引同步点、必要的分页/删除接口。
- 修改：`paste3/ClipboardItem.swift`
  - 增加 SwiftData 索引；如缩略图方案落地，增加 `thumbnailFileName`。
- 新建：`paste3/ClipboardPerformanceProbe.swift`
  - 封装 signpost 和轻量计时，统一埋点。
- 新建：`paste3/ClipboardPasteboardSnapshot.swift`
  - 只在 MainActor 读取 NSPasteboard，生成 Sendable 快照给后台处理。
- 新建：`paste3/ClipboardPreviewImageCache.swift`
  - 按 payload 文件名缓存缩略图，避免卡片重绘重复解码原图。
- 新建：`paste3/ClipboardSearchIndex.swift`
  - 用 SQLite FTS5 维护独立搜索索引，作为 SwiftData 查询前置过滤器。
- 修改：`paste3Tests/paste3Tests.swift`
  - 为 hash、异步候选构建、批量 prune、搜索索引一致性增加测试。

## Task 1: 建立性能基线和埋点

**Files:**
- Create: `paste3/ClipboardPerformanceProbe.swift`
- Modify: `paste3/ClipboardMonitor.swift`
- Modify: `paste3/ClipboardStore.swift`
- Test: `paste3Tests/paste3Tests.swift`

- [ ] **Step 1: 新增性能探针封装**

在 `paste3/ClipboardPerformanceProbe.swift` 新增：

```swift
import Foundation
import OSLog

enum ClipboardPerformanceProbe {
    private static let logger = Logger(subsystem: "top.ysh0566.paste3", category: "performance")

    static func measure<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        do {
            let result = try operation()
            let duration = start.duration(to: .now)
            logger.debug("\(name, privacy: .public) completed in \(String(describing: duration), privacy: .public)")
            return result
        } catch {
            let duration = start.duration(to: .now)
            logger.error("\(name, privacy: .public) failed in \(String(describing: duration), privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}
```

- [ ] **Step 2: 给关键链路加测量点**

在 `ClipboardMonitor.poll()` 中包住候选构建和插入：

```swift
let candidate = ClipboardPerformanceProbe.measure("clipboard.candidate") {
    ClipboardClassifier.candidate(from: pasteboard, source: source)
}
guard let candidate else {
    return
}

try ClipboardPerformanceProbe.measure("clipboard.insert") {
    try ClipboardStore(modelContext: modelContext).insert(candidate)
}
```

在 `ClipboardStore.itemsPage(...)` 中包住每次 `modelContext.fetch`：

```swift
let candidates = try ClipboardPerformanceProbe.measure("clipboard.itemsPage.fetch") {
    try modelContext.fetch(descriptor)
}
```

- [ ] **Step 3: 添加非功能测试确保 probe 不改变返回值**

在 `paste3Tests/paste3Tests.swift` 末尾新增：

```swift
@Test func performanceProbeReturnsOperationResult() throws {
    let result = try ClipboardPerformanceProbe.measure("test.probe") {
        "ok"
    }

    #expect(result == "ok")
}
```

- [ ] **Step 4: 运行测试**

Run:

```bash
xcodebuild test -project paste3.xcodeproj -scheme paste3 -destination platform=macOS -derivedDataPath /private/tmp/paste3-derived
```

Expected: `** TEST SUCCEEDED **`

## Task 2: 降低过期清理和基础查询成本

**Files:**
- Modify: `paste3/ClipboardItem.swift`
- Modify: `paste3/ClipboardStore.swift`
- Test: `paste3Tests/paste3Tests.swift`

- [ ] **Step 1: 给高频查询字段加 SwiftData 索引**

在 `ClipboardItem` 的 `@Model` 定义附近增加索引宏。实施时使用当前 Xcode 支持的 SwiftData `#Index` 语法，目标字段固定为：

```swift
#Index<ClipboardItem>(
    [\.contentHash],
    [\.createdAt],
    [\.kindRawValue]
)
@Model
final class ClipboardItem {
    ...
}
```

如果当前 Xcode 对 `#Index` 语法报错，改用等价的 SwiftData 官方索引写法；字段集合不变。

- [ ] **Step 2: 将 prune 改为分批删除**

在 `ClipboardStore` 增加批量大小常量：

```swift
private enum ClipboardStoreBatching {
    static let pruneBatchSize = 250
}
```

将 `pruneExpiredItemsIfNeeded()` 改为循环分批：

```swift
func pruneExpiredItemsIfNeeded() throws {
    guard let cutoffDate = retentionPeriod.cutoffDate(relativeTo: referenceDateProvider()) else {
        return
    }

    while true {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { item in
                item.createdAt < cutoffDate
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = ClipboardStoreBatching.pruneBatchSize

        let expiredItems = try modelContext.fetch(descriptor)
        guard !expiredItems.isEmpty else {
            return
        }

        for item in expiredItems {
            try deletePayloadIfNeeded(for: item)
            modelContext.delete(item)
        }
        try modelContext.save()
    }
}
```

- [ ] **Step 3: 添加批量 prune 测试**

在 `paste3Tests/paste3Tests.swift` 新增：

```swift
@Test func storePrunesExpiredItemsInBatches() throws {
    let now = Date()
    let context = try makeContext()
    let store = ClipboardStore(
        modelContext: context,
        retentionPeriod: ClipboardRetentionPeriod.find(id: "day-1"),
        referenceDateProvider: { now }
    )
    let source = ClipboardSource(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")

    for index in 0..<620 {
        let candidate = try #require(ClipboardClassifier.candidate(from: "old \(index)", source: source))
        let item = try #require(try store.insert(candidate))
        item.createdAt = now.addingTimeInterval(-2 * 24 * 60 * 60 - TimeInterval(index))
    }

    let freshCandidate = try #require(ClipboardClassifier.candidate(from: "fresh", source: source))
    let fresh = try #require(try store.insert(freshCandidate))
    fresh.createdAt = now
    try context.save()

    try store.pruneExpiredItemsIfNeeded()

    let allItems = try store.items()
    #expect(allItems.map(\.text) == ["fresh"])
}
```

- [ ] **Step 4: 运行测试**

Run:

```bash
xcodebuild test -project paste3.xcodeproj -scheme paste3 -destination platform=macOS -derivedDataPath /private/tmp/paste3-derived
```

Expected: `** TEST SUCCEEDED **`

## Task 3: 将 payload hash 和候选构建移出 MainActor

**Files:**
- Create: `paste3/ClipboardPasteboardSnapshot.swift`
- Modify: `paste3/ClipboardClassifier.swift`
- Modify: `paste3/ClipboardMonitor.swift`
- Modify: `paste3/ClipboardPayloadStore.swift`
- Test: `paste3Tests/paste3Tests.swift`

- [ ] **Step 1: 让跨任务数据显式 Sendable**

修改 `ClipboardSource`、`ClipboardItemCandidate`、`ClipboardKind`：

```swift
struct ClipboardSource: Equatable, Sendable {
    var appName: String?
    var bundleIdentifier: String?
}

struct ClipboardItemCandidate: Equatable, Sendable {
    var kind: ClipboardKind
    var text: String
    var searchText: String
    var source: ClipboardSource
    var contentHash: String
    var byteSize: Int
    var payloadData: Data?
    var payloadType: String?
}

enum ClipboardKind: String, CaseIterable, Identifiable, Sendable {
    ...
}
```

- [ ] **Step 2: 移除 ClipboardPayloadStore 的 MainActor 约束**

将：

```swift
@MainActor
final class ClipboardPayloadStore {
```

改为：

```swift
final class ClipboardPayloadStore: Sendable {
```

`directoryURL` 已经是 `let`，其余方法只使用局部变量和 `FileManager.default`，不需要共享可变状态。

- [ ] **Step 3: 新增 pasteboard 快照**

在 `paste3/ClipboardPasteboardSnapshot.swift` 新增：

```swift
import Foundation

#if os(macOS)
import AppKit

enum ClipboardPasteboardSnapshot: Sendable, Equatable {
    case file(paths: [String])
    case payload(kind: ClipboardKind, text: String, payloadData: Data, payloadType: String)
    case text(String)
    case genericData(payloadData: Data, payloadType: String)

    @MainActor
    static func capture(from pasteboard: NSPasteboard) -> ClipboardPasteboardSnapshot? {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if !urls.isEmpty {
            return .file(paths: urls.map(\.path))
        }

        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), data.count <= ClipboardClassifier.maxStoredPayloadBytes {
                return .payload(
                    kind: .image,
                    text: ClipboardClassifier.imageSummary(type: type, byteSize: data.count),
                    payloadData: data,
                    payloadType: type.rawValue
                )
            }
        }

        if let data = pasteboard.data(forType: .html), data.count <= ClipboardClassifier.maxStoredPayloadBytes {
            let plainText = pasteboard.string(forType: .string)
            let htmlText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? "HTML Content"
            return .payload(kind: .html, text: plainText?.isEmpty == false ? plainText! : htmlText, payloadData: data, payloadType: NSPasteboard.PasteboardType.html.rawValue)
        }

        if let data = pasteboard.data(forType: .rtf), data.count <= ClipboardClassifier.maxStoredPayloadBytes {
            let plainText = pasteboard.string(forType: .string)
            return .payload(kind: .richText, text: plainText?.isEmpty == false ? plainText! : "Rich Text Content", payloadData: data, payloadType: NSPasteboard.PasteboardType.rtf.rawValue)
        }

        if let text = pasteboard.string(forType: .string) {
            return .text(text)
        }

        for pasteboardItem in pasteboard.pasteboardItems ?? [] {
            for type in pasteboardItem.types where ClipboardClassifier.shouldStoreGenericData(type) {
                guard let data = pasteboardItem.data(forType: type), !data.isEmpty, data.count <= ClipboardClassifier.maxStoredPayloadBytes else {
                    continue
                }
                return .genericData(payloadData: data, payloadType: type.rawValue)
            }
        }

        return nil
    }
}
#endif
```

- [ ] **Step 4: 给快照提供后台 candidate 构建**

在 `ClipboardClassifier` 增加：

```swift
#if os(macOS)
static func candidate(from snapshot: ClipboardPasteboardSnapshot, source: ClipboardSource) async -> ClipboardItemCandidate? {
    await Task.detached(priority: .utility) {
        switch snapshot {
        case .file(let paths):
            return candidate(kind: .file, text: paths.joined(separator: "\n"), payloadData: nil, payloadType: NSPasteboard.PasteboardType.fileURL.rawValue, source: source)
        case .payload(let kind, let text, let payloadData, let payloadType):
            return candidate(kind: kind, text: text, payloadData: payloadData, payloadType: payloadType, source: source)
        case .text(let text):
            return candidate(from: text, source: source)
        case .genericData(let payloadData, let payloadType):
            return candidate(kind: .data, text: "\(payloadType), \(payloadData.count) bytes", payloadData: payloadData, payloadType: payloadType, source: source)
        }
    }.value
}
#endif
```

同时把 `imageSummary` 和 `shouldStoreGenericData` 的访问级别从 `private` 调整为 `static` 内部可见，供 snapshot 使用。

- [ ] **Step 5: 修改 ClipboardMonitor 异步处理**

在 `ClipboardMonitor` 增加状态：

```swift
private var captureTask: Task<Void, Never>?
```

在 `stop()` 中取消：

```swift
captureTask?.cancel()
captureTask = nil
```

在 `poll()` 中把同步 candidate/insert 改为：

```swift
guard let snapshot = ClipboardPasteboardSnapshot.capture(from: pasteboard) else {
    return
}

captureTask?.cancel()
captureTask = Task { @MainActor [modelContext] in
    guard let candidate = await ClipboardClassifier.candidate(from: snapshot, source: source) else {
        return
    }

    do {
        try ClipboardStore(modelContext: modelContext).insert(candidate)
    } catch {
        assertionFailure("Failed to insert clipboard candidate: \(error)")
    }
}
```

- [ ] **Step 6: 添加异步 candidate 测试**

在 `paste3Tests/paste3Tests.swift` 新增：

```swift
#if os(macOS)
@Test func classifierBuildsCandidateFromSnapshotOffMainPath() async throws {
    let source = ClipboardSource(appName: "Preview", bundleIdentifier: "com.apple.Preview")
    let payload = Data([0x89, 0x50, 0x4E, 0x47])
    let snapshot = ClipboardPasteboardSnapshot.payload(
        kind: .image,
        text: "PNG Image, 4 bytes",
        payloadData: payload,
        payloadType: NSPasteboard.PasteboardType.png.rawValue
    )

    let candidate = try #require(await ClipboardClassifier.candidate(from: snapshot, source: source))

    #expect(candidate.kind == .image)
    #expect(candidate.payloadData == payload)
    #expect(candidate.byteSize == 4)
}
#endif
```

- [ ] **Step 7: 运行测试**

Run:

```bash
xcodebuild test -project paste3.xcodeproj -scheme paste3 -destination platform=macOS -derivedDataPath /private/tmp/paste3-derived
```

Expected: `** TEST SUCCEEDED **`

## Task 4: 图片预览缩略图缓存

**Files:**
- Create: `paste3/ClipboardPreviewImageCache.swift`
- Modify: `paste3/ContentView.swift`
- Modify: `paste3/ClipboardStore.swift`
- Test: `paste3Tests/paste3Tests.swift`

- [ ] **Step 1: 新增图片缓存**

在 `paste3/ClipboardPreviewImageCache.swift` 新增：

```swift
import Foundation

#if os(macOS)
import AppKit

@MainActor
final class ClipboardPreviewImageCache: ObservableObject {
    static let shared = ClipboardPreviewImageCache()

    private var imagesByKey: [String: NSImage] = [:]

    func image(for item: ClipboardItem, payloadStore: ClipboardPayloadStore = .shared) -> NSImage? {
        guard item.kind == .image else {
            return nil
        }

        let key = item.payloadFileName ?? item.id.uuidString
        if let image = imagesByKey[key] {
            return image
        }

        let data: Data?
        if let payloadData = item.payloadData {
            data = payloadData
        } else if let payloadFileName = item.payloadFileName {
            data = try? payloadStore.read(fileName: payloadFileName)
        } else {
            data = nil
        }

        guard let data, let image = NSImage(data: data) else {
            return nil
        }

        let thumbnail = image.resizedToFit(maxSide: 512)
        imagesByKey[key] = thumbnail
        return thumbnail
    }

    func removeImage(for item: ClipboardItem) {
        imagesByKey.removeValue(forKey: item.payloadFileName ?? item.id.uuidString)
    }
}

private extension NSImage {
    func resizedToFit(maxSide: CGFloat) -> NSImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxSide else {
            return self
        }

        let scale = maxSide / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        draw(in: CGRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        thumbnail.unlockFocus()
        return thumbnail
    }
}
#endif
```

- [ ] **Step 2: ContentView 改用缓存**

把 `ClipboardItem.previewImage` 扩展改为：

```swift
#if os(macOS)
var previewImage: NSImage? {
    ClipboardPreviewImageCache.shared.image(for: self)
}
#endif
```

- [ ] **Step 3: 删除时清缓存**

在 `ContentView.delete(_:)` 调用 store delete 前增加：

```swift
#if os(macOS)
ClipboardPreviewImageCache.shared.removeImage(for: item)
#endif
```

- [ ] **Step 4: 添加缓存测试**

在 `paste3Tests/paste3Tests.swift` 新增一个测试，使用小 PNG fixture Data 构造 `ClipboardItem`，连续两次调用 `ClipboardPreviewImageCache.shared.image(for:)`，断言第二次返回非 nil 且不会重新读取文件。实现方式：用 `ClipboardPayloadStore.temporaryForTests()` 写入 payload，并用同一个 `ClipboardItem.payloadFileName` 调用两次。

- [ ] **Step 5: 运行测试**

Run:

```bash
xcodebuild test -project paste3.xcodeproj -scheme paste3 -destination platform=macOS -derivedDataPath /private/tmp/paste3-derived
```

Expected: `** TEST SUCCEEDED **`

## Task 5: 引入搜索索引，减少大历史 contains 扫描

**Files:**
- Create: `paste3/ClipboardSearchIndex.swift`
- Modify: `paste3/ClipboardStore.swift`
- Modify: `paste3/Paste3AppDelegate.swift`
- Test: `paste3Tests/paste3Tests.swift`

- [ ] **Step 1: 新增 FTS5 搜索索引封装**

在 `paste3/ClipboardSearchIndex.swift` 新增一个 `@MainActor final class ClipboardSearchIndex`，职责：

```swift
@MainActor
final class ClipboardSearchIndex {
    static let shared = ClipboardSearchIndex()

    func upsert(_ item: ClipboardItem) throws
    func delete(itemID: UUID) throws
    func searchIDs(primaryTerm: String, limit: Int, offset: Int) throws -> [UUID]
    func rebuild(from items: [ClipboardItem]) throws
}
```

实现使用 SQLite3：

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_search
USING fts5(item_id UNINDEXED, search_text, tokenize = 'unicode61');
```

`upsert` 先按 `item_id` 删除旧记录，再插入 `item.id.uuidString` 和 `item.searchText`。`searchIDs` 使用：

```sql
SELECT item_id FROM clipboard_search
WHERE clipboard_search MATCH ?
LIMIT ? OFFSET ?;
```

查询参数使用 `primaryTerm + "*"`，最后仍由 `ClipboardSearchQuery.matches` 二次校验，避免索引只做候选集时改变高级 filter 语义。

- [ ] **Step 2: Store 写入/删除同步索引**

在 `ClipboardStore.insert(_:)` 成功保存后增加：

```swift
try ClipboardSearchIndex.shared.upsert(item)
```

在 `delete(_:)` 和 `deleteAll()` 中同步删除或重建：

```swift
try ClipboardSearchIndex.shared.delete(itemID: item.id)
```

批量 prune 删除每个 item 时也调用 `delete(itemID:)`。

- [ ] **Step 3: itemsPage 使用索引预筛选**

在 `itemsPage(...)` 中，当 `primarySearchTerm` 非空且没有 `matchingItemIDs` 时，先从索引拿候选 ID：

```swift
let indexedItemIDs: [UUID]?
if hasPrimarySearchTerm && !hasItemIDScope {
    indexedItemIDs = try ClipboardSearchIndex.shared.searchIDs(
        primaryTerm: primarySearchTerm,
        limit: candidateLimit,
        offset: candidateOffset
    )
} else {
    indexedItemIDs = nil
}
```

如果 `indexedItemIDs` 非空，把它作为 `scopedItemIDs` 加进 SwiftData predicate；如果索引返回空，直接结束循环。高级语法仍走已有 `query.matches(...)` 二次过滤。

- [ ] **Step 4: 首次启动或索引缺失时 rebuild**

在 `Paste3AppDelegate.applicationDidFinishLaunching(_:)` 的末尾调用：

```swift
rebuildSearchIndexIfNeeded()
```

并在 `Paste3AppDelegate` 增加：

```swift
private func rebuildSearchIndexIfNeeded() {
    Task { @MainActor in
        let context = ModelContext(Paste3ModelContainer.shared)
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5_000

        guard let items = try? context.fetch(descriptor) else {
            return
        }

        try? ClipboardSearchIndex.shared.rebuild(from: items)
    }
}
```

如果启动 rebuild 对大库有明显阻塞，把这段移到 `.utility` 任务并分批 fetch；不要阻塞 app 启动。

- [ ] **Step 5: 添加搜索索引一致性测试**

新增测试：

```swift
@Test func searchIndexReturnsInsertedClipboardItemIDs() throws {
    let context = try makeContext()
    let store = ClipboardStore(
        modelContext: context,
        retentionPeriod: ClipboardRetentionPeriod.find(id: "forever")
    )
    let source = ClipboardSource(appName: "Terminal", bundleIdentifier: "com.apple.Terminal")

    let first = try #require(try store.insert(try #require(ClipboardClassifier.candidate(from: "kubectl get pods", source: source))))
    _ = try store.insert(try #require(ClipboardClassifier.candidate(from: "ordinary note", source: source)))

    let ids = try ClipboardSearchIndex.shared.searchIDs(primaryTerm: "kubectl", limit: 10, offset: 0)

    #expect(ids.contains(first.id))
}
```

测试需要让 `ClipboardSearchIndex` 支持注入临时数据库 URL，避免污染用户真实索引。

- [ ] **Step 6: 运行测试**

Run:

```bash
xcodebuild test -project paste3.xcodeproj -scheme paste3 -destination platform=macOS -derivedDataPath /private/tmp/paste3-derived
```

Expected: `** TEST SUCCEEDED **`

## Task 6: 验收和性能对比

**Files:**
- Modify: `CHANGELOG.md`
- Optional Modify: `README.md`

- [ ] **Step 1: 对比场景**

至少验证四个场景：

1. 复制 200k 字符文本，快速面板仍能在 1 秒内响应。
2. 复制 10-20MB 图片，菜单栏/快捷面板不出现明显卡顿。
3. 构造 5k 条历史记录，搜索普通关键词时首屏结果在 300ms 内返回。
4. 构造 600+ 过期历史记录，启动或打开历史窗口不会一次性长时间卡住。

- [ ] **Step 2: 记录命令和结果**

Run:

```bash
xcodebuild test -project paste3.xcodeproj -scheme paste3 -destination platform=macOS -derivedDataPath /private/tmp/paste3-derived
git diff --check
```

Expected:

```text
** TEST SUCCEEDED **
```

`git diff --check` 无输出。

- [ ] **Step 3: 更新变更记录**

在 `CHANGELOG.md` 增加中文条目：

```markdown
- 优化剪贴板捕获和历史查询性能：大 payload 处理移出主线程，过期记录分批清理，图片预览使用缩略图缓存，并为大历史搜索增加索引预筛选。
```

## 风险和回退策略

- 异步捕获可能改变快速连续复制时的插入顺序。验收时需要连续复制 5 条不同内容，确认最终历史顺序仍按完成时或复制时的预期排序；如果顺序不可接受，在 `ClipboardPasteboardSnapshot` 增加 `capturedAt` 并用它初始化 `ClipboardItem.createdAt`。
- 搜索索引可能和 SwiftData 数据不一致。所有搜索结果必须用 `ClipboardSearchQuery.matches` 二次校验；索引缺失时必须 fallback 到现有 SwiftData 查询。
- FTS5 查询默认是 token 语义，不完全等同任意 substring。上线前需确认是否接受搜索语义更偏向词/前缀；若不能接受，保留短词和非词字符 query 的旧路径。
- 图片缓存会增加内存占用。缓存只存 512px 缩略图；如内存压力明显，改成 `NSCache<NSString, NSImage>` 并设置 `countLimit`。

## 完成定义

- 所有新增测试和现有测试通过。
- `git diff --check` 通过。
- 复制大文本、大图片、搜索 5k 历史、清理 600+ 过期记录四个场景都有手动或自动验证结果。
- 用户可感知行为不变，除非明确接受搜索从任意 substring 调整为 token/前缀语义。
