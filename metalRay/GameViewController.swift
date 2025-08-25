//
//  GameViewController.swift
//  metalRay
//
//  Created by Liam Murphy on 2025/08/24.
//

import Cocoa
import MetalKit

class TracerMTKView: MTKView {

    override func keyDown(with event: NSEvent) {
        print("Key pressed: \(event.charactersIgnoringModifiers ?? "")")
    }

    override func mouseMoved(with event: NSEvent) {
        print("Mouse moved: dx=\(event.deltaX), dy=\(event.deltaY)")
    }

    override var acceptsFirstResponder: Bool { true }

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


        self.view.window?.makeFirstResponder(mtkView)

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
    }
}


