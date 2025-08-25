//
//  GameViewController.swift
//  metalRay
//
//  Created by Liam Murphy on 2025/08/24.
//

import Cocoa
import MetalKit

class TracerMTKView: MTKView {
    private var trackingArea: NSTrackingArea?
    weak var inputDelegate: RendererInputDelegate?

    override func keyDown(with event: NSEvent) {
        inputDelegate?.didKeyDown(event.charactersIgnoringModifiers ?? " ")
    }

    override func keyUp(with event: NSEvent) {
        inputDelegate?.didKeyUp(event.charactersIgnoringModifiers ?? " ")
    }

    override func mouseMoved(with event: NSEvent) {
        inputDelegate?.didMoveMouse(deltaX: Float(event.deltaX), deltaY: Float(event.deltaY))
    }

    override func becomeFirstResponder() -> Bool {
        NSCursor.hide()
        return true
    }


    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let ta = trackingArea { removeTrackingArea(ta) }
        let options: NSTrackingArea.Options = [
            .mouseMoved,            // deliver mouseMoved(with:)
            .inVisibleRect,         // track whatever is visible (no manual rect math)
            .activeInKeyWindow,     // only when window is key
            .enabledDuringMouseDrag // still get moves while dragging
        ]
        trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
        super.updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let win = window else { return }

        // 1) Opt in to continuous mouse-move events
        win.acceptsMouseMovedEvents = true

        // 2) Make this view first responder (useful for keyDown, and often for consistent event routing)
        win.makeFirstResponder(self)
        updateTrackingAreas()
    }
}



// Our macOS specific view controller
class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!

    override func loadView() {
        let v = TracerMTKView(frame: CGRect(x: 0, y: 0, width: 800, height: 800), device: MTLCreateSystemDefaultDevice())
        self.view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? TracerMTKView else {
            print("View attached to GameViewController is not an TracerMTKView")
            return
        }


        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer
        mtkView.inputDelegate = renderer
    }
}

