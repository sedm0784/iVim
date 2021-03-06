//
//  VimFontsManager.swift
//  iVim
//
//  Created by Terry on 5/9/17.
//  Copyright © 2017 Boogaloo. All rights reserved.
//

import UIKit

extension FileManager {
    func url(for subdirectoryName: String?, under parentSearchPathDirectory: SearchPathDirectory, in parentSearchPathDomain: SearchPathDomainMask = .userDomainMask) -> URL? {
        do {
            let parent = try self.url(
                for: parentSearchPathDirectory,
                in: parentSearchPathDomain,
                appropriateFor: nil,
                create: true)
            let path: URL
            if let subname = subdirectoryName {
                path = parent.appendingPathComponent(subname)
            } else {
                path = parent
            }
            return try self.createDirectoryIfNecessary(path)
        } catch {
            return nil
        }
    }
    
    func createDirectoryIfNecessary(_ url: URL) throws -> URL? {
        guard !self.fileExists(atPath: url.path) else { return url }
        try self.createDirectory(at: url, withIntermediateDirectories: true)
        
        return url
    }
}

private let userFontsURL: URL? = FileManager.default.url(for: "Fonts", under: .libraryDirectory)
private let defaultFontSize = CGFloat(14)
private let systemFontsFile = "systemFonts"

let gFM = VimFontsManager.shared

final class VimFontsManager: NSObject {
    static let shared = VimFontsManager()
    private override init() {
        super.init()
        self.registerFonts()
    }
    
    var name = ""
    var size = defaultFontSize
    var fonts = [FontInfo]()
    var cache = [String: FontCache]()
}

extension VimFontsManager {
    private func registerSystemFonts() {
        guard let url = Bundle.main.url(forResource: systemFontsFile, withExtension: "plist"),
            let names = NSArray(contentsOf: url) as? [String] else { return }
        for n in names {
            let i = FontInfo(name: n, type: .system)
            self.fonts.append(i)
            self.cache[n] = FontCache(postScriptName: n)
        }
        self.name = names[0]
    }
    
    private func registerUserFonts() {
        guard let path = userFontsURL else { return }
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: path.path)
            for f in contents {
                let i = FontInfo(name: f, type: .user)
                self.fonts.append(i)
            }
        } catch {
            NSLog("Failed to register user fonts: \(error)")
        }
    }
    
    fileprivate func registerFonts() {
        self.registerSystemFonts()
        self.registerUserFonts()
    }
    
    private var printableAvailableFonts: String {
        var s = "Available fonts:"
        for (i, f) in self.fonts.enumerated() {
            let isCurrent = f.name == self.name
            s += "\n\t\(isCurrent ? "*" : "")\(i + 1)"
                + "\t\(f.type.abrivation)"
                + "\t\(f.name)"
                + "\(isCurrent ? "\t\(self.size)" : "")"
        }
        
        return s
    }
    
    func showAvailableFonts(withCommand cmd: String?) {
        showContent(self.printableAvailableFonts, withCommand: cmd)
    }
    
    private func setGUIFont(_ info: String) {
        do_cmdline_cmd("set guifont=\(info.spaceEscaped)")
    }
    
    private func infoForKey(_ key: String) -> FontInfo? {
        return self.fonts.first { $0.name.hasPrefix(key) }
    }
    
    private func infoAtIndex(_ index: Int) -> FontInfo? {
        let i = index - 1
        if i >= 0 && i < self.fonts.count {
            return self.fonts[i]
        } else {
            return nil
        }
    }
    
    private func showErrorForFontName(_ n: String) {
        let err = n.int == nil ? "matching '\(n)'" : "at index \(n)"
        showError("Cannot find font \(err)")
    }
    
    func selectFont(with arg: String) {
        let args = arg.components(separatedBy: .whitespaces)
        let size = args.count > 1 ? args[1].cgFloat : nil
        
        let n = args[0]
        let name: String?
        if n == "_" {
            name = self.name
        } else if let i = n.int {
            name = self.infoAtIndex(i)?.name
        } else {
            name = self.infoForKey(n)?.name
        }
        
        if size == self.size && (name == nil || name == self.name) {
            return
        }
        
        if name == nil && size == nil {
            self.showErrorForFontName(n)
        } else {
            let s = size != nil ? ":h\(Int(size!))" : ""
            self.setGUIFont("\(name ?? self.name)\(s)")
        }
    }
    
    func deleteFont(with arg: String) {
        let info: FontInfo?
        if let i = arg.int {
            info = self.infoAtIndex(i)
        } else {
            info = self.infoForKey(arg)
        }
        guard let i = info else { return self.showErrorForFontName(arg) }
        guard i.type == .user else {
            return showError("Font '\(i.name)' is not an user font")
        }
        self.deleteFont(with: i)
    }
    
    private func deleteFont(with info: FontInfo) {
        guard let i = self.fonts.index(where: { $0 == info }),
            let path = userFontsURL?.appendingPathComponent(info.name)
            else { return }
        do {
            try FileManager.default.removeItem(at: path)
        } catch {
            showError("Failed to delete font '\(info.name)'")
            return
        }
        self.fonts.remove(at: i)
        if self.name == info.name { //if the deleted font was in use, change to the first font
            self.selectFont(with: "1")
        }
        self.uncacheUserFont(with: info.name)
        showMessage("Deleted font '\(info.name)'")
    }
    
    private func uncacheUserFont(with name: String) {
        guard let font = self.cache[name]?.cgFont else { return }
        if !CTFontManagerUnregisterGraphicsFont(font, nil) {
            NSLog("Failed to unregistered font \(name)")
        }
        self.cache[name] = nil
    }
}

extension VimFontsManager {
    private var currentPostScriptName: String {
        return self.postScriptName(for: self.name)!
    }
    
    private func parseFontInfo(_ fi: String) -> (String, CGFloat?) {
        guard let r = fi.range(of: ":h") else { return (fi, nil) }
        let n = fi.substring(to: r.lowerBound)
        let s = fi.substring(from: r.upperBound).cgFloat
        
        return (n, s)
    }
    
    private func fontInfo(with info: String?) -> (String, CGFloat) {
        guard let i = info else { return (self.currentPostScriptName, self.size) }
        let (n, s) = self.parseFontInfo(i)
        let postScriptName: String
        if let fn = self.postScriptName(for: n) {
            self.name = n
            postScriptName = fn
        } else {
            postScriptName = self.currentPostScriptName
        }
        if let s = s {
            self.size = s
        }
        
        return (postScriptName, self.size)
    }
    
    private func prepareUserFont(with name: String) -> String? {
        guard let path = userFontsURL?.appendingPathComponent(name),
            let dp = CGDataProvider(url: path as CFURL)
            else { return nil }
        _ = UIFont() //to overcome the CGFontCreate hanging bug: http://stackoverflow.com/a/40256390/723851
        let font = CGFont(dp)
        guard let psName = font.postScriptName as String?,
            CTFontManagerRegisterGraphicsFont(font, nil) else { return nil }
        self.cache[name] = FontCache(postScriptName: psName, cgFont: font)
        
        return psName
    }
    
    private func postScriptName(for name: String) -> String? {
        if let cached = self.cache[name]?.postScriptName { return cached }
        guard let info = self.fonts.first(where: { $0.name == name }) else { return nil }
        
        return self.prepareUserFont(with: info.name)
    }
    
    func initializeFont(_ info: String?) -> (CTFont, CGFloat, CGFloat, CGFloat) {
        let (fn, fs) = self.fontInfo(with: info)
        let rawFont = CTFontCreateWithName(fn as CFString, fs, nil)
        
        var glyph = CTFontGetGlyphWithName(rawFont, "0" as CFString)
        var advances = CGSize.zero
        CTFontGetAdvancesForGlyphs(rawFont, .horizontal, &glyph, &advances, 1)
        
        let ascent = CTFontGetAscent(rawFont)
        let descent = CTFontGetDescent(rawFont)
        let leading = CTFontGetLeading(rawFont)
        let padding = CGFloat(0)
        let advances_width = advances.width
        let char_ascent = ascent + padding
        let char_width = floor(advances_width)
        let char_height = ascent + descent + leading + padding * 2
        
        let scaleX: CGFloat = char_width / advances_width
        let scaleY: CGFloat = -scaleX
        var transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        
        return (CTFontCreateCopyWithAttributes(rawFont, fs, &transform, nil),
                char_ascent, char_width, char_height)
    }
}

extension VimFontsManager {
    private func showErrorForImportingFont(with fileName: String) -> Bool {
        showError("Failed to import font \\\"\(fileName)\\\"")
        
        return false
    }
    
    func importFont(with fileName: String) -> Bool {
        guard let url = URL.inboxDirectory?.appendingPathComponent(fileName),
            let dst = userFontsURL?.appendingPathComponent(fileName)
            else { return self.showErrorForImportingFont(with: fileName) }
        do {
            try FileManager.default.moveItem(at: url, to: dst)
        } catch {
            NSLog("Failed to move font: \(error)")
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                NSLog("Failed to delete font: \(error)")
            }
            return self.showErrorForImportingFont(with: fileName)
        }
        let fi = FontInfo(name: fileName, type: .user)
        self.fonts.append(fi)
        showMessage("Imported font \\\"\(fileName)\\\"")
        
        return true
    }
}

enum FontType {
    case system
    case user
    
    var abrivation: String {
        switch self {
        case .system: return "s"
        case .user: return "u"
        }
    }
}

struct FontInfo {
    let name: String
    let type: FontType
}

func ==(lfi: FontInfo, rfi: FontInfo) -> Bool {
    return lfi.type == rfi.type && lfi.name == rfi.name
}

struct FontCache {
    let postScriptName: String
    let cgFont: CGFont?
    
    init(postScriptName: String, cgFont: CGFont? = nil) {
        self.postScriptName = postScriptName
        self.cgFont = cgFont
    }
}

extension String {
    private var number: NSNumber? {
        return NumberFormatter().number(from: self)
    }
    
    var cgFloat: CGFloat? {
        return self.number.flatMap { CGFloat($0) }
    }
    
    var int: Int? {
        return self.number as? Int
    }
}

extension URL {
    var isSupportedFont: Bool {
        switch self.pathExtension {
        case "ttf", "otf": return true
        default: return false
        }
    }
}
