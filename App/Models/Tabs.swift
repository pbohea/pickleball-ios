import HotwireNative
import UIKit

private let mapTab = HotwireTab(
    title: "Map",
    image: UIImage(systemName: "map")!,
    url: baseURL.appending(path: "map")
)

//private let menuTab = HotwireTab(
//    title: "Menu",
//    image: UIImage(systemName: "menucard")!,
//    url: baseURL.appending(path: "menu")
//)

private let eventsTab = HotwireTab(
        title: "Home",
        image: UIImage(systemName: "music.microphone")!,
        url: baseURL.appending(path: "/")
)

extension HotwireTab {
    static let all = [
        eventsTab,
        mapTab
        //menuTab
    ]
}
