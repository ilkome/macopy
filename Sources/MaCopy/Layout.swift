import SwiftUI

enum Layout {
    static let rowHeight: CGFloat = 48
    static let visibleRows = 9
    static let searchHeight: CGFloat = 44
    static let tabsHeight: CGFloat = 36
    static let defaultListWidth: CGFloat = 380
    static let defaultPreviewWidth: CGFloat = 360
    static let splitDividerWidth: CGFloat = 6
    static let minListWidth: CGFloat = 260
    static let minPreviewWidth: CGFloat = 240

    static let defaultDomainsWidth: CGFloat = 180
    static let defaultUrlListWidth: CGFloat = 300
    static let minDomainsWidth: CGFloat = 120
    static let minUrlListWidth: CGFloat = 180
    static let minUrlPreviewWidth: CGFloat = 200

    static let defaultFolderListWidth: CGFloat = 180
    static let defaultFolderItemsWidth: CGFloat = 300
    static let minFolderListWidth: CGFloat = 120
    static let minFolderItemsWidth: CGFloat = 180
    static let minFolderPreviewWidth: CGFloat = 200

    static var panelWidth: CGFloat {
        defaultListWidth + splitDividerWidth + defaultPreviewWidth
    }
    static var maxListWidth: CGFloat {
        panelWidth - splitDividerWidth - minPreviewWidth
    }
    static var listHeight: CGFloat { rowHeight * CGFloat(visibleRows) }
    static var panelHeight: CGFloat {
        searchHeight + 1 + tabsHeight + 1 + listHeight
    }

    static var urlMaxDomainsWidth: CGFloat {
        panelWidth - splitDividerWidth * 2 - minUrlListWidth - minUrlPreviewWidth
    }
    static func urlMaxListWidth(domains: CGFloat) -> CGFloat {
        panelWidth - splitDividerWidth * 2 - domains - minUrlPreviewWidth
    }
    static func urlPreviewWidth(domains: CGFloat, list: CGFloat) -> CGFloat {
        max(
            minUrlPreviewWidth,
            panelWidth - splitDividerWidth * 2 - domains - list
        )
    }

    static var folderMaxListWidth: CGFloat {
        panelWidth - splitDividerWidth * 2 - minFolderItemsWidth - minFolderPreviewWidth
    }
    static func folderMaxItemsWidth(list: CGFloat) -> CGFloat {
        panelWidth - splitDividerWidth * 2 - list - minFolderPreviewWidth
    }
    static func folderPreviewWidth(list: CGFloat, items: CGFloat) -> CGFloat {
        max(
            minFolderPreviewWidth,
            panelWidth - splitDividerWidth * 2 - list - items
        )
    }
}

let otherDomainKey = "__other__"
let domainSectionPrefix = "domain-"
let folderSectionPrefix = "folder-"
