import Foundation

/// Watches a directory for changes, coalescing bursts into a single callback.
///
/// The hook rewrites session files on every tool call, so a debounce keeps a
/// busy agent from driving a reload per event.
final class DirectoryWatcher {
    private let url: URL
    private let debounce: TimeInterval
    private let onChange: () -> Void

    private var descriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(url: URL, debounce: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    func start() {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
            queue: .main)

        source.setEventHandler { [weak self] in self?.schedule() }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }

        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    deinit { stop() }
}
