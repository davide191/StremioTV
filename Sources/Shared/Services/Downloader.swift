import Foundation

/// Délégué `URLSession` des téléchargements — **jamais** isolé MainActor : ses
/// méthodes sont appelées sur la file série de la session (arrière-plan). Il ne
/// possède pas la session (le `DownloadStore` la crée avec ce délégué) et ne
/// touche jamais directement l'état du store : il repasse sur le MainActor via
/// `Task { @MainActor in DownloadStore.shared.… }`, en ne faisant traverser que
/// des valeurs `Sendable` (String, URL, Int64, Data).
///
/// Point critique : dans `didFinishDownloadingTo`, le fichier temporaire est
/// supprimé par iOS **dès le retour** de la méthode — le déplacement doit donc
/// être fait SYNCHRONEMENT ici, avant tout `await`/`Task`.
final class Downloader: NSObject, URLSessionDownloadDelegate {
    private let paths = DownloadPaths()
    private var lastPercent: [String: Int] = [:]   // throttle (file délégué série → sûr)

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        let written = totalBytesWritten
        let total = totalBytesExpectedToWrite
        let percent = total > 0 ? Int(Double(written) / Double(total) * 100) : -1
        guard lastPercent[id] != percent else { return }   // n'émet qu'au changement de %
        lastPercent[id] = percent
        Task { @MainActor in
            DownloadStore.shared.updateProgress(id: id, written: written, total: total)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        lastPercent[id] = nil
        let staged = paths.stagingURL(id: id)
        let fm = FileManager.default
        do {
            try? fm.createDirectory(at: paths.dir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: staged.path) { try fm.removeItem(at: staged) }
            try fm.moveItem(at: location, to: staged)   // SYNCHRONE, obligatoire
        } catch {
            let reason = error.localizedDescription
            Task { @MainActor in DownloadStore.shared.markFailed(id: id, reason: reason, resumeData: nil) }
            return
        }
        Task { @MainActor in DownloadStore.shared.finishDownload(id: id, stagedAt: staged) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let error = error as NSError? else { return } // nil = succès
        lastPercent[id] = nil
        // Les annulations (pause / suppression) sont pilotées par le store lui-même.
        if error.code == NSURLErrorCancelled { return }
        let resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let reason = error.localizedDescription
        Task { @MainActor in DownloadStore.shared.markFailed(id: id, reason: reason, resumeData: resumeData) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in DownloadStore.shared.callBackgroundCompletionHandler() }
    }
}
