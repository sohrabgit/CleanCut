import CleanCutKit

/// Guided capture's wording: what to do, never what's wrong with the photo.
extension CaptureIssue {
    var tip: String {
        switch self {
        case .noSubject: "Point the camera at your product"
        case .cutOff: "Step back, part of the product is cut off"
        case .tooFar: "Move closer to fill the frame"
        case .tooDark: "Find more light"
        case .tooBright: "Too bright, move out of direct light"
        case .blurry: "Hold still, the photo is blurry"
        case .glare: "Tilt the product to lose the glare"
        }
    }

    var systemImage: String {
        switch self {
        case .noSubject: "viewfinder"
        case .cutOff: "rectangle.dashed"
        case .tooFar: "plus.magnifyingglass"
        case .tooDark: "sun.min"
        case .tooBright: "sun.max.trianglebadge.exclamationmark"
        case .blurry: "hand.raised"
        case .glare: "sparkle"
        }
    }

    static let readyTip = "Looks great, take the photo"
}

extension CaptureCheck {
    var title: String {
        switch self {
        case .framing: "In frame"
        case .light: "Light"
        case .sharpness: "Sharp"
        case .glare: "No glare"
        }
    }
}
