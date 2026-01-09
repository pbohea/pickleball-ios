import HotwireNative
import UIKit

private let homeTab = HotwireTab(
    title: "Home",
    image: UIImage(systemName: "house")!,
    url: baseURL
)

private let uploadTab = HotwireTab(
    title: "Upload",
    image: UIImage(systemName: "video")!,
    url: baseURL.appendingPathComponent("upload")
)

extension HotwireTab {
    static let all = [
        homeTab,
        uploadTab
    ]
}
