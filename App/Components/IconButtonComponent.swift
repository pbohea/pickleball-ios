import HotwireNative
import UIKit

class IconButtonComponent: BridgeComponent {
    override class var name: String { "icon-button" }

    private struct MessageData: Decodable {
        let systemName: String
        let url: String?
    }

    override func onReceive(message: Message) {
        guard let data: MessageData = message.data() else { return }

        let image = UIImage(systemName: data.systemName)
        let action = UIAction { [weak self] _ in
            guard let self else { return }
            Task { try? await self.reply(to: message.event, with: ["url": data.url ?? ""]) }
        }
        let button = UIBarButtonItem(image: image, style: .plain, target: nil, action: nil)
        button.primaryAction = action

        let viewController = delegate?.destination as? UIViewController
        viewController?.navigationItem.rightBarButtonItem = button
    }
}
