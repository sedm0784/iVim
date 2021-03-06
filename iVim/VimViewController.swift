//
//  ViewController.swift
//  iVim
//
//  Created by Lars Kindler on 27/10/15.
//  Refactored by Terry Chou
//  Copyright © 2015 Boogaloo. All rights reserved.
//

import UIKit
import MobileCoreServices

enum blink_state {
    case none     /* not blinking at all */
    case off     /* blinking, cursor is not shown */
    case on        /* blinking, cursor is shown */
}

final class VimViewController: UIViewController, UIKeyInput, UITextInput, UITextInputTraits {
    var vimView: VimView?
    var hasBeenFlushedOnce = false
    
    var blink_wait: CLong = 1000
    var blink_on: CLong = 1000
    var blink_off: CLong = 1000
    var state: blink_state = .none
    var blinkTimer: Timer?
    
    var documentController: UIDocumentInteractionController?
    
    weak var ctrlButton: OptionalButton?
    var ctrlEnabled: Bool {
        return self.ctrlButton?.isOn(withTitle: "ctrl") ?? false
    }
    
    var textTokenizer: UITextInputStringTokenizer!
    var markedInfo: MarkedInfo?
    var isNormalPending = false
    
    var shouldTuneFrame = true
    lazy var extendedBar: OptionalButtonsBar = self.newExtendedBar()
    var shouldShowExtendedBar = false
    
    var pendingWork: (() -> Void)?
    
    private func registerNotifications() {
        let nfc = NotificationCenter.default
        nfc.addObserver(self, selector: #selector(self.keyboardWillChangeFrame(_:)), name: .UIKeyboardWillChangeFrame, object: nil)
        nfc.addObserver(self, selector: #selector(self.keyboardDidChangeFrame(_:)), name: .UIKeyboardDidChangeFrame, object: nil)
    }
    
    override func viewDidLoad() {
        let v = VimView(frame: self.view.frame)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(v)
        
        self.vimView = v
        
        self.textTokenizer = UITextInputStringTokenizer(textInput: self)
        self.registerNotifications()
        
        v.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.click(_:))))
        v.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(self.longPress(_:))))
        
        let scrollRecognizer = UIPanGestureRecognizer(target:self, action:#selector(self.scroll(_:)))
        scrollRecognizer.minimumNumberOfTouches = 2
        scrollRecognizer.maximumNumberOfTouches = 2
        v.addGestureRecognizer(scrollRecognizer)
        
        let mouseRecognizer = UIPanGestureRecognizer(target:self, action:#selector(self.pan(_:)))
        mouseRecognizer.minimumNumberOfTouches = 1
        mouseRecognizer.maximumNumberOfTouches = 1
        v.addGestureRecognizer(mouseRecognizer)
        
        self.inputAssistantItem.leadingBarButtonGroups = []
        self.inputAssistantItem.trailingBarButtonGroups = []
        
        self.toggleExtendedBar()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        #if  FEAT_GUI
        //print("Hallo!")
        #endif
    }
    
    func resetKeyboard() {
        self.shouldTuneFrame = false
        self.resignFirstResponder()
        self.becomeFirstResponder()
        self.shouldTuneFrame = true
    }
    
    func click(_ sender: UITapGestureRecognizer) {
        self.resetKeyboard()
        self.unmarkText()
        let clickLocation = sender.location(in: sender.view)
        gui_send_mouse_event(0, Int32(clickLocation.x), Int32(clickLocation.y), 1, 0)
    }
    
    func longPress(_ sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else { return }
        self.toggleExtendedBar()
    }
    
    func flush() {
        if !self.hasBeenFlushedOnce {
            self.hasBeenFlushedOnce = true
            DispatchQueue.main.async { self.becomeFirstResponder() }
        }
        self.vimView?.flush()
    }
    
    private func changeCursor(after timeInterval: CLong) {
        self.blinkTimer?.invalidate()
        let delay = TimeInterval(timeInterval) / 1000.0
        self.blinkTimer = Timer.scheduledTimer(timeInterval: delay, target: self, selector: #selector(self.blinkCursor), userInfo: nil, repeats: false)
    }
    
    func markNeedsDisplay() {
        self.vimView?.markNeedsDisplay()
    }
    
    func blinkCursor() {
        switch self.state {
        case .on:
            gui_undraw_cursor()
            self.state = .off
            self.changeCursor(after: self.blink_off)
        case .off, .none:
            gui_update_cursor(1, 0)
            self.state = .on
            self.changeCursor(after: self.blink_on)
        }
        self.markNeedsDisplay()
    }
    
    func startBlink() {
        self.state = .on
        gui_update_cursor(1, 0)
        self.changeCursor(after: self.blink_wait)
    }
    
    func stopBlink() {
        self.blinkTimer?.invalidate()
        self.state = .none
        gui_update_cursor(1, 0)
        self.blinkTimer = nil
    }

    
   override var canBecomeFirstResponder : Bool {
        return self.hasBeenFlushedOnce
    }
    
    override var canResignFirstResponder : Bool {
        return true
    }
    
    
   // MARK: UIKeyInput
    private func addToInputBuffer(_ text: String) {
        let length = text.utf8Length
        add_to_input_buf(text, Int32(length))
        self.markNeedsDisplay()
    }
    
    var hasText: Bool {
        return true
    }
    
    func escapingText(_ text: String) -> String {
        if self.ctrlEnabled {
            self.ctrlButton?.tryRestore()
            return text.uppercased().ctrlModified
        } else if text == "\n" {
            return keyCAR.unicoded
        } else {
            return text
        }
    }
    
    func insertText(_ text: String) {
        self.addToInputBuffer(self.escapingText(text))
    }
    
    func deleteBackward() {
        self.insertText(keyBS.unicoded)
    }
    
    // Mark: UITextInputTraits
    
    var autocapitalizationType = UITextAutocapitalizationType.none
    var keyboardType = UIKeyboardType.default
    var autocorrectionType = UITextAutocorrectionType.no
    
    fileprivate func toggleExtendedBar() {
        self.shouldShowExtendedBar = !self.shouldShowExtendedBar
        self.resignFirstResponder()
        self.becomeFirstResponder()
    }
    
    //MARK: OnScreen Keyboard Handling
    private func tuneFrameAccordingToKeyboard(_ notification: Notification) {
        guard self.shouldTuneFrame,
            let frame = (notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as AnyObject).cgRectValue,
            let v = self.view,
            let window = v.window
            else { return }
        let screenHeight = UIScreen.main.bounds.height
        let isSplited = screenHeight - frame.origin.y > frame.height
        let newHeight = isSplited ? screenHeight : window.convert(frame, to: v).origin.y
        let tuning = {
            guard v.frame.size.height != newHeight else { return }
            v.frame.size.height = newHeight
        }
        guard let pw = self.pendingWork else { return tuning() }
        CATransaction.begin()
        tuning()
        CATransaction.setCompletionBlock {
            pw()
            self.pendingWork = nil
        }
        CATransaction.commit()
    }
    
    func keyboardWillChangeFrame(_ notification: Notification) {
        self.tuneFrameAccordingToKeyboard(notification)
    }
    
    func keyboardDidChangeFrame(_ notification: Notification) {
        self.tuneFrameAccordingToKeyboard(notification)
    }
    
    func waitForChars(_ wtime: Int) -> Bool {
        if input_available() > 0 { return true }
        let expirationDate = wtime > -1 ? Date(timeIntervalSinceNow: TimeInterval(wtime) * 0.001) : .distantFuture
        repeat {
            RunLoop.current.acceptInput(forMode: .defaultRunLoopMode, before: expirationDate)
            if input_available() > 0 {
                return true
            }
        } while expirationDate > Date()
        
        return false
    }
    
    func pan(_ sender: UIPanGestureRecognizer) {
        guard let v = self.vimView else { return }
        let clickLocation = sender.location(in: v)
        let event: Int32
        switch sender.state {
        case .began: event = mouseLEFT
        case .ended: event = mouseRELEASE
        default: event = mouseDRAG
        }
        gui_send_mouse_event(event, Int32(clickLocation.x), Int32(clickLocation.y), 1, 0)
    }
    
    func scroll(_ sender: UIPanGestureRecognizer) {
        if sender.state == .began {
//            self.becomeFirstResponder()
            let clickLocation = sender.location(in: sender.view)
            gui_send_mouse_event(0, Int32(clickLocation.x), Int32(clickLocation.y), 1, 0)
        }
        
        guard let v = self.vimView else { return }
        let translation = sender.translation(in: v)
        let charHeight = v.char_height
        var diffY = translation.y / charHeight
        
        if diffY <= -1 {
            sender.setTranslation(CGPoint(x: 0, y: translation.y - ceil(diffY) * charHeight), in: v)
        }
        if diffY >= 1 {
            sender.setTranslation(CGPoint(x: 0, y: translation.y - floor(diffY) * charHeight), in: v)
        }
        while diffY <= -1 {
            self.addToInputBuffer("E".ctrlModified)
            diffY += 1
        }
        while diffY >= 1 {
            self.addToInputBuffer("Y".ctrlModified)
            diffY -= 1
        }
    }
    
    func flash(forSeconds s: TimeInterval) {
        guard let v = self.view else { return }
        let fv = UIView(frame: v.bounds)
        fv.backgroundColor = .white
        fv.alpha = 1
        v.addSubview(fv)
        UIView.animate(withDuration: s, animations: {
            fv.alpha = 0
        }) { _ in
            fv.removeFromSuperview()
        }
    }
}

extension VimViewController {
    private var shareRect: CGRect {
        return CGRect(x: 0, y: self.view.bounds.size.height - 10, width: 10, height: 10)
    }
   
    func showShareSheet(url: URL?, text: String?) {
        if let url = url {
            self.documentController = UIDocumentInteractionController(url: url)
            self.documentController?.presentOptionsMenu(from: self.shareRect, in: self.view, animated: true)
        } else if let text = text {
            let avc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            avc.popoverPresentationController?.sourceRect = self.shareRect
            avc.popoverPresentationController?.sourceView = self.view
            self.present(avc, animated: true)
        }
    }
}

extension String {
    var escaped: String {
        return "\\<\(self)>"
    }
    
    var ctrlModified: String {
        let c = getCTRLKeyCode(self)
        return c != 0 ? c.unicoded : ""
    }
    
    var nsstring: NSString {
        return self as NSString
    }
    
    var nsLength: Int {
        return self.nsstring.length
    }
    
    var utf8Length: Int {
        return self.lengthOfBytes(using: .utf8)
    }
    
    var spaceEscaped: String {
        return self.replacingOccurrences(of: " ", with: "\\ ")
    }
}

private extension Int {
    var unicoded: String {
        return UnicodeScalar(self)!.description
    }
}

extension Int32 {
    var unicoded: String {
        return Int(self).unicoded
    }
}
