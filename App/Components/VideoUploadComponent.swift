import HotwireNative
import UIKit
import WebKit

class VideoUploadComponent: BridgeComponent {
    override class var name: String { "video-upload" }

    private struct MessageData: Decodable {
        let uploadUrl: String
        let notes: String?
        let csrfToken: String?
    }

    private struct UploadReply: Codable {
        let redirect_url: String?
        let error: String?
    }

    private var uploadURL: URL?
    private var notes: String = ""
    private var csrfToken: String?
    private var source: String = "camera"

    override func onReceive(message: Message) {
        guard message.event == "capture" else { return }
        guard let data: MessageData = message.data() else { return }

        uploadURL = URL(string: data.uploadUrl)
        notes = data.notes ?? ""
        csrfToken = data.csrfToken

        presentSourcePicker()
    }

    private func presentSourcePicker() {
        guard let viewController = delegate?.destination as? UIViewController else { return }

        let alert = UIAlertController(title: "Upload Video", message: nil, preferredStyle: .actionSheet)

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Record Video", style: .default) { [weak self] _ in
                self?.source = "camera"
                self?.presentPicker(sourceType: .camera)
            })
        }

        alert.addAction(UIAlertAction(title: "Choose From Library", style: .default) { [weak self] _ in
            self?.source = "library"
            self?.presentPicker(sourceType: .photoLibrary)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        viewController.present(alert, animated: true)
    }

    private func presentPicker(sourceType: UIImagePickerController.SourceType) {
        guard let viewController = delegate?.destination as? UIViewController else { return }

        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.mediaTypes = ["public.movie"]
        picker.videoQuality = .typeHigh
        picker.allowsEditing = false
        picker.delegate = pickerDelegate
        pickerDelegate.onCancel = { [weak picker] in
            picker?.dismiss(animated: true)
        }
        pickerDelegate.onPick = { [weak self, weak picker] url in
            picker?.dismiss(animated: true)
            self?.handlePickedVideo(url)
        }

        viewController.present(picker, animated: true)
    }

    private func handlePickedVideo(_ fileURL: URL?) {
        guard let fileURL else {
            replyFailure("No video file was selected.")
            return
        }
        uploadVideo(fileURL: fileURL)
    }

    private func uploadVideo(fileURL: URL) {
        guard let uploadURL else {
            replyFailure("Upload URL is missing.")
            return
        }

        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let cookieStorage = HTTPCookieStorage.shared
            cookies.forEach { cookieStorage.setCookie($0) }
            self.performUpload(to: uploadURL, fileURL: fileURL)
        }
    }

    private func performUpload(to uploadURL: URL, fileURL: URL) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let body = self.createMultipartBody(boundary: boundary, fileURL: fileURL)
            request.httpBody = body

            let session = URLSession(configuration: .default)
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    self.replyFailure("Upload failed: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    self.replyFailure("Upload failed: server error \(httpResponse.statusCode).")
                    return
                }

                guard let data else {
                    self.replyFailure("Upload failed: empty response.")
                    return
                }

                do {
                    let reply = try JSONDecoder().decode(UploadReply.self, from: data)
                    self.replySuccess(reply)
                } catch {
                    let fallback = UploadReply(redirect_url: nil, error: "Upload failed: invalid response.")
                    self.replySuccess(fallback)
                }
            }
            task.resume()
        }
    }

    private func createMultipartBody(boundary: String, fileURL: URL) -> Data {
        var body = Data()

        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        appendField(name: "video[notes]", value: notes)
        appendField(name: "video[source]", value: source)

        let filename = fileURL.lastPathComponent
        let mimeType = "video/mp4"
        let fileData = (try? Data(contentsOf: fileURL)) ?? Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"video[original_video]\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        return body
    }

    private func replyFailure(_ message: String) {
        let reply = UploadReply(redirect_url: nil, error: message)
        replySuccess(reply)
    }

    private func replySuccess(_ reply: UploadReply) {
        Task { try? await self.reply(to: "capture", with: reply) }
    }

    private lazy var pickerDelegate = PickerDelegate()
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

private final class PickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var onPick: ((URL?) -> Void)?
    var onCancel: (() -> Void)?

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        onCancel?()
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
    ) {
        let fileURL = info[.mediaURL] as? URL
        onPick?(fileURL)
    }
}
