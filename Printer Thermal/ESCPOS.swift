//
//  ESCPOS.swift
//  Printer Thermal
//
//  Created by NPSK Macbook on 30/07/26.
//

struct ESCPOS {
    // Basic Control
    static let initPrinter: [UInt8]       = [0x1B, 0x40]          // ESC @ - Resets printer to defaults
    static let lineFeed: [UInt8]          = [0x0A]                // LF - Prints buffer and feeds one line
    
    // Formatting & Alignment
    static let alignLeft: [UInt8]         = [0x1B, 0x61, 0x00]    // ESC a 0 - Align text left
    static let alignCenter: [UInt8]       = [0x1B, 0x61, 0x01]    // ESC a 1 - Center text
    static let alignRight: [UInt8]        = [0x1B, 0x61, 0x02]    // ESC a 2 - Align text right
    
    // Text Styling
    static let boldOn: [UInt8]            = [0x1B, 0x45, 0x01]    // ESC E 1 - Bold text on
    static let boldOff: [UInt8]           = [0x1B, 0x45, 0x00]    // ESC E 0 - Bold text off
    static let doubleSize: [UInt8]        = [0x1B, 0x21, 0x30]    // ESC ! 48 - High & wide text
    static let normalSize: [UInt8]        = [0x1B, 0x21, 0x00]    // ESC ! 0 - Default text size
    static let underlineOn: [UInt8]       = [0x1B, 0x2D, 0x01]    // ESC - 1 - Underline text on
    static let underlineOff: [UInt8]      = [0x1B, 0x2D, 0x00]    // ESC - 0 - Underline text off

    // Hardware Actions
    static let paperCutFull: [UInt8]      = [0x1D, 0x56, 0x00]    // GS V 0 - Cuts paper fully
    static let paperCutPartial: [UInt8]   = [0x1D, 0x56, 0x01]    // GS V 1 - Cuts paper partially
    static let openCashDrawer: [UInt8]    = [0x1B, 0x70, 0x00, 0x19, 0xFF] // ESC p 0 25 255 - Pulse pin 2
}
