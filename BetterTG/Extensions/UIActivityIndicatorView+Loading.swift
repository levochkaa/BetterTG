// UIActivityIndicatorView+Loading.swift

import UIKit

extension UIActivityIndicatorView {
    /// Starts or stops the indicator and keeps a stopped one hidden, so VoiceOver does not find an invisible
    /// "Progress halted" element over the control it stands in for.
    func setLoading(_ loading: Bool) {
        if loading {
            isHidden = false
            startAnimating()
        } else {
            stopAnimating()
            isHidden = true
        }
        // Hidden alone did not drop the indicator inside a visual-effect toolbar from the accessibility tree.
        accessibilityElementsHidden = !loading
    }
}
