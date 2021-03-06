//
//  VimViewController+UITextInput.swift
//  iVim
//
//  Created by Terry on 5/31/17.
//  Copyright © 2017 Boogaloo. All rights reserved.
//

import UIKit

extension VimViewController {
    private var currentText: String? {
        return self.markedInfo?.text
    }
    
    private var currentTextLength: Int {
        return self.currentText?.nsLength ?? 0
    }
    
    func text(in range: UITextRange) -> String? {
        //print(#function)
        guard let range = range as? VimTextRange else { return nil }
        
        return self.currentText?.nsstring.substring(with: range.nsrange)
    }
    
    func replace(_ range: UITextRange, withText text: String) {
        //print(#function)
    }
    
    var selectedTextRange: UITextRange? {
        get {
            //print(#function)
            return VimTextRange(range: self.markedInfo?.selectedRange)
        }
        set {
            guard let nv = newValue as? VimTextRange else { return }
            self.markedInfo?.selectedRange = nv.nsrange
        }
    }
    
    var markedTextRange: UITextRange? {
        //print(#function)
        return self.markedInfo?.range
    }
    
    var markedTextStyle: [AnyHashable : Any]? {
        get { return nil }
        set { return }
    }
    
    private func handleNormalMode(_ text: String?) -> Bool {
        guard let text = text, !text.isEmpty else { return true }
        if !self.isNormalPending {
            gAddNonCSITextToInputBuffer(self.escapingText(text))
            switch text {
            case "f", "F", "t", "T", "r": self.isNormalPending = true
            default: break
            }
            self.resetKeyboard()
            return true
        }
        
        return false
    }
    
    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        //print(#function)
        if is_in_normal_mode() && self.handleNormalMode(markedText) {
            return
        }
        if self.markedInfo == nil {
            self.markedInfo = MarkedInfo()
            self.becomeFirstResponder()
        }
        self.markedInfo?.didGetMarkedText(markedText, selectedRange: selectedRange, pending: self.isNormalPending)
        self.flush()
        self.markNeedsDisplay()
    }
    
    func unmarkText() {
        //print(#function)
        guard let info = self.markedInfo else { return }
        if self.isNormalPending {
            gAddNonCSITextToInputBuffer(info.text)
            self.isNormalPending = false
        }
        self.markedInfo?.didUnmark()
        self.markedInfo = nil
    }
    
    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        //print(#function)
        return VimTextRange(start: fromPosition.position, end: toPosition.position)
    }
    
    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        //print(#function)
        let loc = position.position.location
        let new = loc + offset
        guard new >= 0 && new <= self.currentTextLength else { return nil }
        
        return VimTextPosition(location: new)
    }
    
    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        //print(#function)
        let newOffset: Int
        switch direction {
        case .left, .up: newOffset = offset
        case .right, .down: newOffset = -offset
        }
        
        return self.position(from: position, offset: newOffset)
    }
    
    var beginningOfDocument: UITextPosition {
        //print(#function)
        return VimTextPosition(location: 0)
    }
    
    var endOfDocument: UITextPosition {
        //print(#function)
        return VimTextPosition(location: self.currentTextLength)
    }
    
    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        //print(#function)
        let lhp = position.position.location
        let rhp = other.position.location
        if lhp == rhp {
            return .orderedSame
        } else if lhp < rhp {
            return .orderedAscending
        } else {
            return .orderedDescending
        }
    }
    
    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        //print(#function)
        return toPosition.position.location - from.position.location
    }
    
    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        //print(#function)
        let r = (range as! VimTextRange).nsrange
        let newLoc: Int
        switch direction {
        case .up, .left: newLoc = r.location
        case .down, .right: newLoc = r.location + r.length
        }
        
        return VimTextPosition(location: newLoc)
    }
    
    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        //print(#function)
        let oldLoc = position.position.location
        let newLoc: Int
        switch direction {
        case .up, .left: newLoc = oldLoc - 1
        case .down, .right: newLoc = oldLoc
        }
        
        return VimTextRange(location: newLoc, length: 1)
    }
    
    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> UITextWritingDirection {
        //print(#function)
        return .leftToRight
    }
    
    func setBaseWritingDirection(_ writingDirection: UITextWritingDirection, for range: UITextRange) {
        //print(#function)
        return
    }
    
    func firstRect(for range: UITextRange) -> CGRect {
        //print(#function)
        return .zero
    }
    
    func caretRect(for position: UITextPosition) -> CGRect {
        //print(#function)
        return .zero
    }
    
    func closestPosition(to point: CGPoint) -> UITextPosition? {
        //print(#function)
        return nil
    }
    
    func selectionRects(for range: UITextRange) -> [Any] {
        //print(#function)
        return []
    }
    
    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        //print(#function)
        return nil
    }
    
    func characterRange(at point: CGPoint) -> UITextRange? {
        //print(#function)
        return nil
    }
    
    var inputDelegate: UITextInputDelegate? {
        get { return nil }
        set { return }
    }
    
    var tokenizer: UITextInputTokenizer {
        //print(#function)
        return self.textTokenizer
    }
    
    var textInputView: UIView {
        //print(#function)
        return self.vimView!
    }
    
    func cancelCurrentMarkedText() {
        self.markedInfo?.cancelled = true
        self.resetKeyboard()
    }
}

private extension UITextPosition {
    var position: VimTextPosition {
        return self as! VimTextPosition
    }
}

class VimTextPosition: UITextPosition {
    var location: Int
    
    init(location: Int) {
        self.location = location
        super.init()
    }
    
    convenience init(position: VimTextPosition) {
        self.init(location: position.location)
    }
}

class VimTextRange: UITextRange {
    var location: Int
    var length: Int
    
    init?(location: Int, length: Int) {
        guard location >= 0 && length >= 0 else { return nil }
        self.location = location
        self.length = length
        super.init()
    }
    
    convenience init?(range: NSRange?) {
        guard let r = range else { return nil }
        self.init(location: r.location, length: r.length)
    }
    
    convenience init?(start: VimTextPosition, end: VimTextPosition) {
        self.init(location: start.location, length: end.location - start.location)
    }
    
    override var start: UITextPosition {
        return VimTextPosition(location: self.location)
    }
    
    override var end: UITextPosition {
        return VimTextPosition(location: self.location + self.length)
    }
    
    override var isEmpty: Bool {
        return self.length == 0
    }
    
    var nsrange: NSRange {
        return NSMakeRange(self.location, self.length)
    }
}

struct MarkedInfo {
    var selectedRange = NSMakeRange(0, 0)
    var text = ""
    var cancelled = false
}

extension MarkedInfo {
    var range: VimTextRange {
        return VimTextRange(location: 0, length: self.text.nsLength)!
    }
    
    private func deleteBackward(for times: Int) {
        gAddTextToInputBuffer(keyBS.unicoded, for: times)
    }
    
    private func deleteOldMarkedText() {
        guard !self.text.isEmpty else { return }
        let oldLen = self.text.nsLength
        let offset = oldLen - self.selectedRange.location
        move_cursor_right(offset)
        self.deleteBackward(for: oldLen)
    }
    
    mutating func didGetMarkedText(_ text: String?, selectedRange: NSRange, pending: Bool) {
        guard let text = text else { return }
        if !pending {
            self.deleteOldMarkedText()
            gAddNonCSITextToInputBuffer(text)
            let offset = text.nsLength - selectedRange.location
            move_cursor_left(offset)
        }
        self.text = text
        self.selectedRange = selectedRange
    }
    
    mutating func didUnmark() {
        guard self.cancelled else { return }
        self.deleteOldMarkedText()
        self.cancelled = false
    }
}
